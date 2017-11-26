%% Header
%==========================================================================
% This testbench simulations transmission mode 5 on subframe 7.
% Results can be compared to "./dlsim -x5 -S7 -R1 -u1" with perfect chest
% No OFDM Modulation and Demodulation is applied!
%
% Author: Sebastian Wagner
% Date: 24-07-2012
%
%==========================================================================

clear all;
close all;
clear mex;

addpath('/home/eurecom/OAI/openairinterface5g/cmake_targets/mexfiles/build')
addpath('/home/eurecom/OAI/openairinterface5g/cmake_targets/mexfiles/src/mex/mexOAI')

% profile on;
tic
%% System parameters

nt=4;
nr=4;
N = 1; % number of frames (codewords)
nSNR =1;
SNRdB = 15;
n_layers=4;

MCS = 2;
j = sqrt(-1);
amp = 1/32;
XFORMS = 0;
% LLRs are computed for 8RE make sure enough valid memory is allocated
LLR_GUARD_SAMPLES = 8*6; % max mod_order 6 for 8 REs
reimag=2;


%% Initialize simparms
simparms = InitSimparms_SU_MIMO4x4( nt, nr, n_layers, MCS, N, SNRdB);

%% Random data, same seed as in dlsim.c
[tmp simparms.tseeds] = Taus(1,simparms.tseeds);

%% Index of REs carrying data
data_idx = [901:1400 1501:2300 2401:3500 3601:4200];
data_idx_int = [1801:2800 3001:4600 4801:7000 7201:8400]; % [Re Im] format
data_idx_int_r = data_idx_int(1:2:length(data_idx_int));
data_idx_int_i = data_idx_int(2:2:length(data_idx_int));



%% Allocate memory

H = zeros(simparms.NB_ANTENNAS_RX,simparms.NB_ANTENNAS_TX);
noise = zeros(simparms.NB_ANTENNAS_RX,simparms.nb_re/n_layers);



llr0 = zeros(simparms.codeword.G, 1,'int16');

% Received signal in fixed point
y_fxp = zeros(simparms.NB_ANTENNAS_RX,simparms.nb_re_per_frame,'int16');

% FXP received signal with transformed dimensions.
% This is an analog of rx_dataF[aatx*simparms.NB_ANTENNAS_RX+aarx]
y_fxp_t = zeros(reimag*simparms.nb_re_per_frame,simparms.NB_ANTENNAS_RX,'int16');

% Received signal after compensation
ymf0 = zeros(reimag*simparms.nb_re_per_frame,simparms.NB_ANTENNAS_RX*simparms.NB_ANTENNAS_TX,'int16');

% Effective channel will contain the channel estimate at pilot positions
Heff0 = zeros(reimag*simparms.nb_re_per_frame,simparms.NB_ANTENNAS_RX*simparms.NB_ANTENNAS_TX,'int16');
Hmag0 = zeros(reimag*simparms.nb_re_per_frame,simparms.NB_ANTENNAS_RX*simparms.NB_ANTENNAS_TX,'int16');
Hmagb0 = zeros(reimag*simparms.nb_re_per_frame,simparms.NB_ANTENNAS_RX*simparms.NB_ANTENNAS_TX,'int16');
rho10 = zeros(reimag*simparms.nb_re_per_frame,simparms.NB_ANTENNAS_RX*simparms.NB_ANTENNAS_TX,'int16');

%Decoded bits
dec_bit =zeros(1,simparms.codeword(1).G);

%% XFORMS
if (XFORMS)
	scrsz = get(0,'ScreenSize');
	figure('Position',[1 scrsz(4)/2 scrsz(3)/2 scrsz(4)/2])
	subplot(1,2,1);
	xlim([1 simparms.codeword(1).G]);
	title('LLRs of UE 0');
	
	fig_llr0 = scatter(1:simparms.codeword(1).G,llr0,'.','YDataSource','llr0');
	
	subplot(1,2,2);
	title('MF output of UE 0');
	fig_ymf = scatter(ymf0(data_idx_int_r),ymf0(data_idx_int_i),'.','XDataSource','ymf0(data_idx_int_r)','YDataSource','ymf0(data_idx_int_i)');
end

%% Encode and modulate transmit signal
% The same data is used throughout the simulation -> saves time
[data0 simparms.tseeds] = Taus(simparms.codeword(1).TBS/8,simparms.tseeds);
% Add 4 bytes CRC
data0 = [data0; zeros(4,1,'uint8')];

edata0 = DlschEncoding(data0,simparms,simparms.codeword(1));

%% Modulation edata_enc contains symbols, and not bits.
edata_enc(:,1)= simparms.codeword(1).base2*double(reshape(edata0,simparms.codeword(1).mod_order,simparms.nb_re));

% x is scaled symbol
x(:,1) = simparms.codeword(1).const(edata_enc(:,1)+1);
Ptx = sum(diag(x'*x))/(simparms.nb_re/n_layers); % average transmit power per RE

%% Layer Mapping
  x_L1 = x(1:4:length(x));
  x_L2 = x(2:4:length(x));
  x_L3 = x(3:4:length(x));
  x_L4 = x(4:4:length(x));
  
  x_total_layer = [x_L1 x_L2 x_L3 x_L4].';
  
  

%% Loop over SNRs
 for iSNR=1:length(simparms.snr)
 	cSNR = simparms.snr(iSNR); % current SNR
 	%% Loop over Frames
 	for n=1:simparms.n_frames
 		n
 		
		%% Channel
 		% Rayleigh channel, constant for whole codeblock/frame, always 2x2
 		H(1:nr,1:nt) = (randn(nr,nt) + j*randn(nr,nt))/sqrt(2);
		
		%% Transmit signal (frequency domain)
				
		%% Noise		
		sigma2 = (Ptx/cSNR);
		noise(1:nr,:) = sqrt(sigma2).*(randn(nr,simparms.nb_re/n_layers) + j*randn(nr,simparms.nb_re/n_layers))./sqrt(2);
		
		%% Received signal
		y = H*x_total_layer + noise; 
        
        Hh_H= H'*H;
        Hh_H_inv=inv(Hh_H);
        
		% Translating to Q15 format
		y_fxp_data = int16(floor(y*pow2(15)));
        
		H_fxp = int16(fix(H*floor(amp/sqrt(2)*pow2(15)))); % Perfect Chest	
        
        Hh_H_fxp = int16(fix(Hh_H*floor(amp/sqrt(2)*pow2(15)))); 
        
        Hh_H_inv = int16(fix(Hh_H_inv*floor(amp/sqrt(2)*pow2(15)))); 
        
        
		
		% insert dummy pilots
		y_fxp(1:simparms.NB_ANTENNAS_RX,data_idx) = y_fxp_data;

        % reorder for processing
 		H_fxp_t = repmat([real(H_fxp(:)) imag(H_fxp(:))]',simparms.nb_re_per_frame,1);
        Hh_H_fxp_t = repmat([real(Hh_H_fxp(:)) imag(Hh_H_fxp(:))]',simparms.nb_re_per_frame,1);
        Hh_H_inv_t = repmat([real(Hh_H_inv(:)) imag(Hh_H_inv(:))]',simparms.nb_re_per_frame,1);
        for ii=1:(nr)
            y_fxp_t(:,ii) = reshape([real(y_fxp(ii,:)); imag(y_fxp(ii,:))],2*simparms.nb_re_per_frame,1);	
        end
 		%% Compute Scaling
    	avg = DlschChannelLevel(H_fxp_t,simparms);
        [max_av_ch, index_max]=max(avg(:))
        
        simparms.log2_maxh = max(double(Log2Approx(max_av_ch))-13,0);		
        
        %% Inner receiver loop
  		llrp = 1; % LLR pointer
        for symbol = 4:14
  			idxs = 2*(symbol-1)*simparms.nb_re_per_symbol + 1;
 			idxe = 2*(symbol-1)*simparms.nb_re_per_symbol + 2*simparms.nb_re_per_symbol;
 			
 			%% Preprocessing
			[ymf0(idxs:idxe,:),...
				Heff0(idxs:idxe,:)...
				Hmag0(idxs:idxe,:)...
				Hmagb0(idxs:idxe,:)]...
				= DlschChannelCompensation(y_fxp_t,H_fxp_t,simparms,simparms.codeword(1),symbol-1);

            rx_data_comp_tot(idxs:idxe,1)=ymf0(idxs:idxe,1)+ymf0(idxs:idxe,2)+ymf0(idxs:idxe,3)+ymf0(idxs:idxe,4);
            rx_data_comp_tot(idxs:idxe,2)=ymf0(idxs:idxe,5)+ymf0(idxs:idxe,6)+ymf0(idxs:idxe,7)+ymf0(idxs:idxe,8);
            rx_data_comp_tot(idxs:idxe,3)=ymf0(idxs:idxe,9)+ymf0(idxs:idxe,10)+ymf0(idxs:idxe,11)+ymf0(idxs:idxe,12);
            rx_data_comp_tot(idxs:idxe,4)=ymf0(idxs:idxe,13)+ymf0(idxs:idxe,14)+ymf0(idxs:idxe,15)+ymf0(idxs:idxe,16);
            

            
          %  rho10(idxs:idxe,:) = dlsch_dual_stream_correlation_4rx(Heff0,Heff1,simparms,symbol-1);
% 			
% 			% Interfering user
% 			[ymf1(idxs:idxe,:)...
% 				Heff1(idxs:idxe,:)...
% 				Hmag1(idxs:idxe,:)...
% 				Hmagb1(idxs:idxe,:)]...
% 				= DlschChannelCompensation_TM56(y_fxp_t,H_fxp_t,pmi_ext_o,simparms,simparms.codeword(2),symbol-1);
% 			
% 			%% Correlation coefficient
% 			rho10(idxs:idxe,:) = DlschDualStreamCorrelation(Heff0,Heff1,simparms,symbol-1);
% 			
% 			%% Combining
% 			if (nr>1)
% 				[ymf0(idxs:idxe,:)...
% 					ymf1(idxs:idxe,:)...
% 					Hmag0(idxs:idxe,:)...
% 					Hmagb0(idxs:idxe,:)...
% 					Hmag1(idxs:idxe,:)...
% 					Hmagb1(idxs:idxe,:)...
% 					rho10(idxs:idxe,:)]...
% 					= DlschDetectionMrc(ymf0,ymf1,Hmag0,Hmag1,Hmagb0,Hmagb1,rho10,simparms,symbol-1);								
% 			end
% 			
% 			
% 			%% LLR computation
%             llr = DlschIALLR([ymf0(idxs:idxe,1); zeros(LLR_GUARD_SAMPLES,1,'int16')],...
%                 [ymf1(idxs:idxe,1); zeros(LLR_GUARD_SAMPLES,1,'int16')],...
%                 [Hmag0(idxs:idxe,1); zeros(LLR_GUARD_SAMPLES,1,'int16')],...
%                 [Hmag1(idxs:idxe,1); zeros(LLR_GUARD_SAMPLES,1,'int16')],...
%                 [rho10(idxs:idxe,1); zeros(LLR_GUARD_SAMPLES,1,'int16')],...
%                 simparms,...
%                 symbol-1);
% 			
% 			llr0(llrp:llrp+length(llr)-1,:) = llr;
% 			llrp = llrp + length(llr);                        
% 		end
% 		
% 		if (XFORMS)
% 			refreshdata(fig_llr0,'caller');
% 			drawnow;
% 			
% 			refreshdata(fig_ymf,'caller');
% 			drawnow; pause(0.1);
% 		end
% 		
% 		%% Channel decoding
% 		llr0 = -llr0; % invert (since no scrambling applied)				
% 		ret0 = DlschDecoding(llr0,simparms,simparms.codeword(1));						
% 		
% 		% Check if decoded correctly
% 		if (ret0 >= simparms.MAX_TURBO_ITERATIONS)
% 			simparms.frame_errors(iSNR,1) = simparms.frame_errors(iSNR,1) + 1;
 		end
		
	end
	%fprintf('********************SNR = %3.1f dB processed on %s********************\n',real(simparms.snr_db(iSNR)),datestr(now));
	%fprintf('Errors: %d/%d\nPe = %1.5f\n',simparms.frame_errors(iSNR,1),N,simparms.frame_errors(iSNR,1)/N);	
end

%% Post Processing
%  total_frame_erros = sum(simparms.frame_errors,2);
%  fer = total_frame_erros/N;
%  figure; semilogy(SNRdB,fer); grid;
%  
%  disp(fer);
% 
% profile viewer 
toc
