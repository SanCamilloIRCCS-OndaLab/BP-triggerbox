% TriggerBox - MATLAB interface for the Brain Products TriggerBox on Linux
%
% This class provides an interface to the Brain Products TriggerBox device
% on Linux using the FTDI D2XX library (libftd2xx). The TriggerBox is based
% on an FTDI FT2232H chip operating in asynchronous GPIO bitbang mode:
%   - Interface A (output): used to send trigger values (0-255)
%   - Interface B (input):  used to read incoming trigger signals
%
% NOTE: This class requires the ftdi_sio kernel module to be unloaded before
% use, as it conflicts with libftd2xx. Run the following before instantiating:
%   sudo rmmod ftdi_sio && sudo rmmod usbserial
%
% DISCLAIMER: This project is not affiliated with or supported by Brain
% Products GmbH. Official support for the TriggerBox is Windows-only.
%
% Usage:
%   tb = TriggerBox();
%   tb.send(5);              % send trigger 5, auto-reset after 10ms
%   tb.pulse(5, 0.05);       % send trigger 5 for 50ms
%   tb.set(5);               % set output pins to 5 (no auto-reset)
%   tb.reset();              % reset output pins to 0
%   value = tb.read();       % read current state of input pins
%   value = tb.readWait(5);  % wait up to 5s for a non-zero input trigger
%   delete(tb);              % close device and unload library
%
% Organization: IRCCS San Camillo Hospital (Venice, Italy)
% 
% Author:  Alessandro Tonin
%
% License: MIT

classdef TriggerBox < handle
    
    properties (Access = private)
        handleOut
        handleIn
        bytesWritten
        isOutOpen = false
        isInOpen = false
        isLibLoaded = false
    end
    
    properties (Constant, Access = private)
        LibName         = 'libftd2xx'
        BrainProductsID = 0x1103
        TriggerBoxID    = 0x0021
        soLibPath       = '/usr/local/lib/libftd2xx.so'
        hLibPath        = '/usr/local/include/ftd2xx.h'
    end
    
    methods
        
        function obj = TriggerBox()
            % Load the library if not already loaded
            if libisloaded(obj.LibName)
                error('TriggerBox: library %s is already loaded, we imagine an instance of TriggerBox is already open. Call delete() on the existing instance first.', obj.LibName)
            else
                loadlibrary(obj.soLibPath, obj.hLibPath);
            end
            obj.isLibLoaded = true;
            
            % Register Brain Products vendor and product ID with libftd2xx
            % (not in the default FTDI vendor list, must be added explicitly)
            calllib(obj.LibName, 'FT_SetVIDPID', uint32(obj.BrainProductsID), uint32(obj.TriggerBoxID));

            % Get TriggerBox indexes
            [idxA, idxB] = obj.getTriggerBoxIndexes();
            
            % Open interface A (output) by description
            obj.handleOut = libpointer('voidPtr', 0);
            status = calllib(obj.LibName, 'FT_Open', idxA, obj.handleOut);
            if status ~= 0
                error('TriggerBox: could not open output interface (status %d). Make sure ftdi_sio is not loaded.', status);
            end
            obj.isOutOpen = true;
            % Set all pins as output in asynchronous bitbang mode
            status = calllib(obj.LibName, 'FT_SetBitMode', obj.handleOut, uint8(0xFF), uint8(0x01));
            if status ~= 0
                error('TriggerBox: could not set bitbang mode on output interface (status %d).', status);
            end
            
            % Open interface B (input) by description
            obj.handleIn = libpointer('voidPtr', 0);
            status = calllib(obj.LibName, 'FT_Open', idxB, obj.handleIn);
            if status ~= 0
                error('TriggerBox: could not open input interface (status %d). Make sure ftdi_sio is not loaded.', status);
            end
            obj.isInOpen = true;
            % Set all pins as input in asynchronous bitbang mode
            status = calllib(obj.LibName, 'FT_SetBitMode', obj.handleIn, uint8(0x00), uint8(0x01));
            if status ~= 0
                error('TriggerBox: could not set bitbang mode on input interface (status %d).', status);
            end
            
            obj.bytesWritten = libpointer('uint32Ptr', 0);
            fprintf('TriggerBox initialized successfully.\n');
        end
        
        %% OUTPUT
        
        function send(obj, value)
            % Send a trigger value and auto-reset to 0 after 10ms
            obj.pulse(value, 0.01);
        end

        function pulse(obj, value, duration)
            % Send a trigger value and reset to 0 after a custom duration (seconds)
            if nargin < 3
                duration = 0.01;
            end
            obj.set(value);
            pause(duration);
            obj.reset();
        end

        function set(obj, value)
            % Set output pins to value (0-255) without auto-reset
            if value < 0 || value > 255
                error('TriggerBox: value must be between 0 and 255.');
            end
            calllib(obj.LibName, 'FT_Write', obj.handleOut, uint8(value), 1, obj.bytesWritten);
        end
        
        function reset(obj)
            % Reset output pins to 0
            obj.set(0);
        end
        
        %% INPUT
        
        function value = read(obj)
            % Read the current state of the input pins
            pinState = libpointer('uint8Ptr', uint8(0));
            status = calllib(obj.LibName, 'FT_GetBitMode', obj.handleIn, pinState);
            if status ~= 0
                value = -1;
            else
                value = pinState.Value;
            end
        end
        
        function value = readWait(obj, timeout)
            % Poll input pins until a non-zero value is received or timeout (seconds)
            if nargin < 2
                timeout = 5.0;
            end
            t = tic;
            value = -1;
            while toc(t) < timeout
                v = obj.read();
                if v > 0
                    value = v;
                    return;
                end
                pause(0.0001);  % poll every 0.1ms
            end
            warning('TriggerBox: timed out waiting for input trigger.');
        end
        
        %% CLEANUP
        
        function delete(obj)
            % Close output interface if open
            try
                if obj.isOutOpen
                    calllib(obj.LibName, 'FT_Close', obj.handleOut);
                end
            catch
            end
            
            % Close input interface if open
            try
                if obj.isInOpen
                    calllib(obj.LibName, 'FT_Close', obj.handleIn);
                end
            catch
            end
            
            % Unload library
            try
                if obj.isLibLoaded
                    unloadlibrary(obj.LibName);
                end
            catch
            end
            
            
            fprintf('TriggerBox closed successfully.\n');
        end
        
    end

    %% Private helpers
    methods (Access=private)
        function [idxA, idxB] = getTriggerBoxIndexes(obj)
            % Find device indices for TriggerBox A and TriggerBox B
            numDevs = libpointer('uint32Ptr', 0);
            calllib(obj.LibName, 'FT_CreateDeviceInfoList', numDevs);
            
            idxA = -1;
            idxB = -1;
            for i = 0:numDevs.Value-1
                flags       = libpointer('uint32Ptr', 0);
                typePtr     = libpointer('uint32Ptr', 0);
                idPtr       = libpointer('uint32Ptr', 0);
                locIdPtr    = libpointer('uint32Ptr', 0);
                serialNum   = libpointer('int8Ptr', zeros(1, 16, 'int8'));
                description = libpointer('int8Ptr', zeros(1, 64, 'int8'));
                handlePtr   = libpointer('voidPtr', 0);
                calllib(obj.LibName, 'FT_GetDeviceInfoDetail', i, flags, typePtr, idPtr, locIdPtr, serialNum, description, handlePtr);
                desc = char(description.Value);
                if contains(desc, 'TriggerBox A')
                    idxA = i;
                elseif contains(desc, 'TriggerBox B')
                    idxB = i;
                end
            end
            
            if idxA == -1 || idxB == -1
                error('TriggerBox: could not find TriggerBox A and/or TriggerBox B. Make sure ftdi_sio is not loaded.');
            end
        end

    end
    
end