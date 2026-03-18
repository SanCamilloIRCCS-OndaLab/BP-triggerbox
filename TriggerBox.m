classdef TriggerBox < handle
    
    properties (Access = private)
        handleOut
        handleIn
        bytesWritten
    end
    
    properties (Constant, Access=private)
        LibName = 'libftd2xx'
        BrainProductsID = 0x1103
        TriggerBoxID = 0x0021
        soLibPath = '/usr/local/lib/libftd2xx.so'
        hLibPath = '/usr/local/include/ftd2xx.h'
    end
    
    methods
        
        function obj = TriggerBox()
            % Carica la libreria se non è già caricata
            if ~libisloaded(obj.LibName)
                loadlibrary(obj.soLibPath, obj.hLibPath);
            end
            
            % Registra vendor e product Brain Products
            calllib(obj.LibName, 'FT_SetVIDPID', uint32(obj.BrainProductsID), uint32(obj.TriggerBoxID));
            
            % Apri interfaccia 0 (TriggerBox A = output)
            obj.handleOut = libpointer('voidPtr', 0);
            status = calllib(obj.LibName, 'FT_Open', 0, obj.handleOut);
            if status ~= 0
                error('TriggerBox: impossibile aprire interfaccia output (status %d). Verificare che ftdi_sio non sia caricato.', status);
            end
            status = calllib(obj.LibName, 'FT_SetBitMode', obj.handleOut, uint8(0xFF), uint8(0x01));
            if status ~= 0
                error('TriggerBox: impossibile impostare modalità bitbang output (status %d).', status);
            end
            
            % Apri interfaccia 1 (TriggerBox B = input)
            obj.handleIn = libpointer('voidPtr', 0);
            status = calllib(obj.LibName, 'FT_Open', 1, obj.handleIn);
            if status ~= 0
                error('TriggerBox: impossibile aprire interfaccia input (status %d).', status);
            end
            status = calllib(obj.LibName, 'FT_SetBitMode', obj.handleIn, uint8(0x00), uint8(0x01));
            if status ~= 0
                error('TriggerBox: impossibile impostare modalità bitbang input (status %d).', status);
            end
            
            obj.bytesWritten = libpointer('uint32Ptr', 0);
            fprintf('TriggerBox inizializzata correttamente.\n');
        end
        
        %% OUTPUT
        
        function send(obj, value)
            % Invia un trigger e resetta a 0 dopo 10ms
            obj.pulse(value, 0.01);
        end

        function pulse(obj, value, duration)
            % Invia un trigger con durata personalizzata (in secondi)
            if nargin < 3
                duration = 0.01;
            end
            obj.set(value);
            pause(duration);
            obj.reset();
        end

        function set(obj, value)
            % Imposta il valore senza reset automatico
            % Check sul valore
            if value < 0 || value > 255
                error('TriggerBox: il valore deve essere tra 0 e 255.');
            end
            calllib(obj.LibName, 'FT_Write', obj.handleOut, uint8(value), 1, obj.bytesWritten);
        end
        
        function reset(obj)
            % Resetta output a 0
            obj.set(0);
        end

        
        
        %% INPUT
        
        function value = read(obj)
            % Legge lo stato corrente dei pin di input
            pinState = libpointer('uint8Ptr', uint8(0));
            status = calllib('libftd2xx', 'FT_GetBitMode', obj.handleIn, pinState);
            if status ~= 0
                value = -1;
            else
                value = pinState.Value;
            end
        end
        
        function value = readWait(obj, timeout)
            % Attende un trigger in input fino a timeout (secondi)
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
                pause(0.0001);  % polling ogni 0.1ms
            end
            warning('TriggerBox: timeout in attesa del trigger.');
        end
        
        
        %% CHIUSURA
        
        function delete(obj)
            if ~isempty(obj.handleOut)
                calllib(obj.LibName, 'FT_Close', obj.handleOut);
            end
            if ~isempty(obj.handleIn)
                calllib(obj.LibName, 'FT_Close', obj.handleIn);
            end
            if libisloaded(obj.LibName)
                unloadlibrary(obj.LibName);
            end
            fprintf('TriggerBox chiusa correttamente.\n');
        end
        
    end
    
end