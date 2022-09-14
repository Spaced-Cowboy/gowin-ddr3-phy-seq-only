`timescale 1 ps / 1 ps // 1 ps steps, 1 ps precision.

module top
	#(
	// (Only Altera & Gowin for now) Use ALTERA, INTEL, GOWIN, LATTICE, XILINX
	parameter string     FPGA_VENDOR             = "Gowin",

	// With Altera, use Cyclone III, Cyclone IV, Cyclone V, MAX 10,....
	// With Gowin, use GW2A-18 or GW2A-55
	parameter string     FPGA_FAMILY             = "GW2A-18",

	// Use '1' for better FMAX performance, this will add logic cell usage to
	// the BrianHG_DDR3_PHY_SEQ module.
	parameter bit        BHG_OPTIMIZE_SPEED      = 1,

	// It is recommended that you use '1' when running slowest -8 Altera fabric
	// FPGA above 300MHz or Altera -6 fabric above 350MHz.
	// Use '1' for even better FMAX performance or when overclocking the core. 
	// This will increase logic cell usage.							
	parameter bit        BHG_EXTRA_SPEED         = 1,                


	// ****************  System clock generation and operation.
	// PLL source input clock frequency in KHz.
	parameter int        CLK_KHZ_IN              = 27000,

	// Multiply factor to generate the DDR MTPS speed divided by 2.     
	parameter int        CLK_IN_MULT             = 30,               
	
	// Divide factor.  When CLK_KHZ_IN is 25k,50k,75k,100k,125k,150k, 
	// use (correspondingly) 2,4,6,8,10,12.
	parameter int        CLK_IN_DIV              = 4,
	
	// Either "Full", "Half", or "Quarter" speed for the user interface clock.
	// This will effect the controller's interface CMD_CLK output port freq.
	parameter string     INTERFACE_SPEED         = "Quarter",


	// ****************  DDR3 ram chip configuration settings
	// DDR3 CK clock speed in MHz.
	parameter int        DDR3_CK_MHZ              = ((CLK_KHZ_IN*CLK_IN_MULT/CLK_IN_DIV)/1000), 

	// Use 1066: 187E, 1333: -15E, 1600: -125, 1866: -107, or 2133 MHz: 093.
	parameter string     DDR3_SPEED_GRADE        = "-125",

	// Use 0,1,2,4 or 8.  (0=512mb) Caution: Must be correct as ram chip size 
	// affects the tRFC REFRESH period.
	parameter int        DDR3_SIZE_GB            = 1,

	// Use 8 or 16.  The width of each DDR3 ram chip.
	parameter int        DDR3_WIDTH_DQ           = 16,

	// 1, 2, or 4 for the number of DDR3 RAM chips.
	parameter int        DDR3_NUM_CHIPS          = 1,

	// Select the number of DDR3_CLK & DDR3_CLK# output pairs.  
	// Add 1 for every DDR3 Ram chip.
	// These are placed on a DDR DQ or DDR CK# IO output pins.
	parameter int        DDR3_NUM_CK             = (DDR3_NUM_CHIPS),
																	
	// Use for the number of bits to address each row.
	parameter int        DDR3_WIDTH_ADDR         = 13,

	// Use for the number of bits to address each bank.
	parameter int        DDR3_WIDTH_BANK         = 3,

	// Use for the number of bits to address each column.
	parameter int        DDR3_WIDTH_CAS          = 10,

	// The width of the write data mask. 
	// (***Double when using multiple 4 bit DDR3 ram chips.)
	parameter int        DDR3_WIDTH_DM           = (DDR3_WIDTH_DQ*DDR3_NUM_CHIPS/8), 

	// The number of DQS pairs.
	// (***Double when using multiple 4 bit DDR3 ram chips.)
	parameter int        DDR3_WIDTH_DQS          = (DDR3_WIDTH_DQ*DDR3_NUM_CHIPS/8), 

	// Must equal to total bus width across all DDR3 ram chips *8.
	parameter int        DDR3_RWDQ_BITS          = (DDR3_WIDTH_DQ*DDR3_NUM_CHIPS*8), 

	// use 120, 60, 40, 30, 20 Ohm. or 0 to disable ODT.  
	// (On Die Termination during write operation.)
	parameter int        DDR3_ODT_RTT            = 40,

	// use 34 or 40 Ohm. (Output Drive Strength during read operation.)              
	parameter int        DDR3_RZQ                = 40,

	// use 85,95,105. (Peak operating temperature in degrees Celsius.)
	parameter int        DDR3_TEMP               = 85,

	// 270, Select the write and write DQS output clock phase relative to the 
	// DDR3_CLK/CK#
	parameter int        DDR3_WDQ_PHASE          = 270,              

	// 0, Select the read latch clock for the read data and DQS input 
	// relative to the DDR3_CLK.
	parameter int        DDR3_RDQ_PHASE          = 0,

	// Defines the size of the refresh queue where refreshes will have a higher
	// priority than incoming SEQ_CMD_ENA_t command requests.
	// *** Do not go above 8, doing so may break the data sheet's maximum 
	// ACTIVATE-to-PRECHARGE command period.
	parameter bit [4:0]  DDR3_MAX_REF_QUEUE      = 8,

	// Defines the time in 1/10uS until the command IDLE counter will allow 
	// low priority REFRESH cycles.
	// Use 10 for 1uS.  0=disable, 1 for a minimum effect, 127 maximum.
	parameter bit [7:0]  IDLE_TIME_uSx10         = 2,
																	
	// Skip timer during and after reset. ***ONLY use 1 for quick simulations.
	parameter bit        SKIP_PUP_TIMER          = 0,

	// Only supports "ROW_BANK_COL" or "BANK_ROW_COL".  Choose to optimize your 
	// memory access.
	parameter string     BANK_ROW_ORDER          = "ROW_BANK_COL", 


	// ****************  DDR3 controller configuration parameter settings
	
	// Set the width of the SEQ_RDATA_VECT_IN & SEQ_RDATA_VECT_OUT port, 1..64
	parameter int        DDR3_VECTOR_SIZE        = 5,               
	
	// Set the width of the SEQ_RDATA_VECT_IN & SEQ_RDATA_VECT_OUT port, 
	// 1 through 64.
	parameter int        PORT_ADDR_SIZE          = (DDR3_WIDTH_ADDR 
												 + DDR3_WIDTH_BANK 
												 + DDR3_WIDTH_CAS 
												 + (DDR3_WIDTH_DM-1)),

	// When 1, this setting makes the 'SEQ_CMD_ENA_t', 'SEQ_BUSY_t' and 
	// 'SEQ_RDATA_RDY_t' controls activate each time their input/output toggles.
	// When the setting is 0, these controls become active true/enable logic 
	// synchronous to the CMD_CLK
	parameter bit        USE_TOGGLE_OUTPUTS    = 1,  

	// *************************************************************************
	// ****************  BrianHG_DDR3_COMMANDER_2x1 config param settings.
	// Set the total number of DDR3 controller write ports, 1 to 4 max.
	// Use 2 through 16.  This sets the width of each MUX join from the top 
	// PORT inputs down to the final SEQ output.  2 offers the greatest possible 
	// FMAX while making the first layer width = to PORT_TOTAL will minimize MUX 
	// layers to 1, but with a large number of ports, FMAX may take a beating.
	parameter int        PORT_TOTAL              = 1,                
	parameter int        PORT_MLAYER_WIDTH [0:3] = '{2,2,2,2},       

	// *************************************************************************
	// PORT_MLAYER_WIDTH illustration
	// *************************************************************************
	//  PORT_TOTAL = 16, PORT_MLAYER_WIDTH [0:3]  = {4,4,x,x}
	// 		(PORT_MLAYER_WIDTH[0]=4)    
	//		(PORT_MLAYER_WIDTH[1]=4)     
	//		(PORT_MLAYER_WIDTH[2]=N/A) (not used)  	These layers aren't used          
	//		(PORT_MLAYER_WIDTH[3]=N/A) (not used)	since we already reached one  
	//												single port to drive the 
	//                                              DDR3 SEQ
	//  PORT_xxxx[ 0] ---\                               .
	//  PORT_xxxx[ 1] ----== ML10_xxxx[0] ------\
	//  PORT_xxxx[ 2] ---/                       \
	//  PORT_xxxx[ 3] --/                         \
	//                                             \
	//  PORT_xxxx[ 4] ---\                          \
	//  PORT_xxxx[ 5] ----== ML10_xxxx[1] -----------== SEQ_xxxx wires to 
	//  PORT_xxxx[ 6] ---/                          /   DDR3_PHY controller
	//  PORT_xxxx[ 7] --/                          /
	//                                            /
	//  PORT_xxxx[ 8] ---\                       /
	//  PORT_xxxx[ 9] ----== ML10_xxxx[2] ------/
	//  PORT_xxxx[10] ---/                     /
	//  PORT_xxxx[11] --/                     /
	//                                       /
	//  PORT_xxxx[12] ---\                  /
	//  PORT_xxxx[13] ----== ML10_xxxx[3] -/
	//  PORT_xxxx[14] ---/
	//  PORT_xxxx[15] --/
	//
	//
	//  PORT_TOTAL = 16,  PORT_MLAYER_WIDTH [0:3]  = {3,3,3,x}
	//  This will offer a better FMAX compared to {4,4,x,x}, but the final DDR3 
	//  SEQ command has 1 additional clock cycle pipe delay.
	//
	// 		(PORT_MLAYER_WIDTH[0]=3)    
	//		(PORT_MLAYER_WIDTH[1]=3)    
	//		(PORT_MLAYER_WIDTH[2]=3)     No difference if this was 2             
	//		(PORT_MLAYER_WIDTH[3]=N/A)   (not used, we made it down to 1 port)
	//                                                                      
	//  PORT_xxxx[ 0] ---\
	//  PORT_xxxx[ 1] ----== ML10_xxxx[0] --\
	//  PORT_xxxx[ 2] ---/                   \
	//                                        \
	//  PORT_xxxx[ 3] ---\                     \
	//  PORT_xxxx[ 4] ----== ML10_xxxx[1] ------= ML20_xxxx[0] -\
	//  PORT_xxxx[ 5] ---/                     /                 \
	//                                        /                   |
	//  PORT_xxxx[ 6] ---\                   /                    |
	//  PORT_xxxx[ 7] ----== ML10_xxxx[2] --/                     |  
	//  PORT_xxxx[ 8] ---/                                        |   
	//                                                            |    
	//  PORT_xxxx[ 9] ---\                                        |     
	//  PORT_xxxx[10] ----== ML11_xxxx[0] --\                     |      
	//  PORT_xxxx[11] ---/                   \                    |      
	//                                        \                   |        
	//  PORT_xxxx[12] ---\                     \                  |         
	//  PORT_xxxx[13] ----== ML11_xxxx[1] ------= ML20_xxxx[1] ---+-= SEQ_xxxx   .
	//  PORT_xxxx[14] ---/                     /                  |   wires to
	//                                        /                   |   DDR3_PHY
	//  PORT_xxxx[15] ---\                   /                    |   controller
	//         0=[16] ----== ML11_xxxx[2] --/                     |
	//         0=[17] ---/                         				  /
	//                                                           /
	//                                                          /
	//                                                         /
	//                                   0 = ML20_xxxx[2] ----/
	//
	// *************************************************************************

	// Sets the width of each port's VECTOR input and output.
	parameter int        PORT_VECTOR_SIZE   = 16,                

	// *************************************************************************
	// ***** DO NOT CHANGE THE NEXT 4 PARAMETERS FOR THIS VERSION OF THE 
	// ***** BrianHG_DDR3_COMMANDER.sv... **************************************

	// The number of bits available for the read ID.  This will limit the 
	// maximum possible read/write cache modules.
	parameter int        READ_ID_SIZE       = 4,
	
	// Sets the width of the VECTOR for the DDR3_PHY_SEQ controller.  4 bits 
	// for 16 possible read ports.
	parameter int        DDR3_VECTOR_SIZE   = READ_ID_SIZE + 1,

	// Note that this value must be a multiple of 
	// '(8*DDR3_WIDTH_DQ * DDR3_NUM_CHIPS)* burst 8'.
	parameter int        PORT_CACHE_BITS    = (8*DDR3_WIDTH_DM*8),

	// This is the number of LSB address bits which address all the available 
	// 8 bit bytes inside the cache word.
	parameter int        CACHE_ADDR_WIDTH   = $clog2(PORT_CACHE_BITS/8),

	// Sets the starting address bit where a new row & bank begins.
	parameter int        BYTE_INDEX_BITS    = (DDR3_WIDTH_CAS + (DDR3_WIDTH_DM-1)), 
	// *************************************************************************

	// PORT_'feature' = '{port# 0,1,2,3,4,5,,,} Sets the feature for each DDR3 
	// ram controller interface port 0 to port 15.

	// When enabled, the associated port's 'CMD_busy' and 'CMD_ena' ports will 
	// operate in toggle mode where each toggle of the 'CMD_ena' will represent 
	// a new command input and the port is busy whenever the 'CMD_busy' output 
	// is not equal to the 'CMD_ena' input. This is an advanced  feature used 
	// to communicate with the input channel when your source control is 
	// operating at 2x this module's CMD_CLK frequency, or 1/2 CMD_CLK frequency
	// if you have disabled the port's PORT_W_CACHE_TOUT.
	parameter bit        PORT_TOGGLE_INPUT [0:15] = '{  0,  0,  0,  0,  
														0,  0,  0,  0,  
														0,  0,  0,  0,  
														0,  0,  0,  0},

	// Use 8,16,32,64,128, or 256 bits, maximum = 'PORT_CACHE_BITS'
	// As a precaution, this will prune/ignore unused data bits and write masks
	// bits, however, all the data ports will still be 'PORT_CACHE_BITS' bits 
	// and the write masks will be 'PORT_CACHE_WMASK' bits. (a 'PORT_CACHE_BITS' 
	// bit wide data bus has 32 individual mask-able bytes (8 bit words))
	// For ports sizes below 'PORT_CACHE_BITS', the data is stored and received
	// in Big Endian.  
	parameter bit [8:0]  PORT_R_DATA_WIDTH [0:15] = '{  8,128,128,128,
													  128,128,128,128,
													  128,128,128,128,
													  128,128,128,128},
	parameter bit [8:0]  PORT_W_DATA_WIDTH [0:15] = '{  8,128,128,128,
													  128,128,128,128,
													  128,128,128,128,
													  128,128,128,128},

	// Use 0 to 3.  If a port with a higher priority receives a request, even if 
	// another port's request matches the current page, the higher priority port 
	// will take precedence and force the controller to leave the current page.
	parameter bit [1:0]  PORT_PRIORITY     [0:15] = '{  3,  0,  0,  0,
													    0,  0,  0,  0,  
														0,  0,  0,  0,  
														0,  0,  0,  0},

	// Sets the size of the intermediate read command request stack.
	// 24 through 32, default = 24
	// The size of the number of read commands built up in advance while the 
	// read channel waits for the DDR3_PHY_SEQ to return the read request data.
	// Multiple reads must be accumulated to allow an efficient continuous read 
	// burst.
	// IE: Use 16 level deep when running a small data port width like 16 or 32
	// so sequential read cache hits continue through the command input allowing
	// cache miss read req later-on in the req stream to be immediately be sent 
	// to the DDR3_PHY_SEQ before the DDR3 even returns the first read req data.
	parameter int        PORT_READ_STACK   [0:15] = '{ 24, 24, 24, 24, 
													   24, 24, 24, 24, 
													   24, 24, 24, 24, 
													   24, 24, 24, 24},

	// A timeout for the write cache to dump it's contents to ram.
	// 0   = immediate writes, or no write cache.
	// 256 = Wait up to 256 CMD_CLK clock cycles since the previous write req.
	//       to the same 'PORT_CACHE_BITS' bit block before writing to ram.  
	//       Write reqs outside the current 'PORT_CACHE_BITS' bit cache block
	//       clears the timer and forces an immediate write.
	parameter bit [8:0]  PORT_W_CACHE_TOUT [0:15] = '{256,256,256,256,
													  256,256,256,256,
													  256,256,256,256,
													  256,256,256,256},


	// A 0 will direct the read cache to indefinitely keep its contents valid 
	// until a new read address is requested outside the the current cache 
	// contents.  Recommended for very slow read cycles where you may manually 
	// read outside the current cached address if you wish to re-read from the 
	// DDR3. A 1 will use the automatic timeout setting below to automatically
	// clear the read cache address.
	parameter bit    PORT_R_CACHE_TOUT_ENA [0:15] = '{  0,  1,  1,  1,
														1,  1,  1,  1,  
														1,  1,  1,  1,  
														1,  1,  1,  1},

	// A timeout for the read cache to consider its contents stale.
	// 0   = Always read from DDR3, or no read caching.
	// 256 = Wait up to 256 CMD_CLK clock cycles since the previous read req 
	//       before considering the cached read stale.
	parameter bit [8:0]  PORT_R_CACHE_TOUT [0:15] = '{256,256,256,256,
													  256,256,256,256,
													  256,256,256,256,
													  256,256,256,256},

	// A 1 will automatically detect an impossible skipped/missing read command 
	// due to multiport cache collision between a read input CMD_ena and output 
	// CMD_read_ready, unfreezing this potential situation.
	parameter bit        PORT_R_WDT_ENA    [0:15] = '{  1,  1,  1,  1,
														1,  1,  1,  1,  
														1,  1,  1,  1,  
														1,  1,  1,  1},


	// When enabled, if an existing read cache exists at the same write request 
	// address, that read's cache will immediately be updated with the new write
	// data. This function may impact the FMAX for the system clock and increase
	// LUT usage.
	// *** Disable when designing a memory read/write testing algorithm.
	parameter bit        PORT_CACHE_SMART  [0:15] = '{  1,  1,  1,  1,  
														1,  1,  1,  1,  
														1,  1,  1,  1,  
														1,  1,  1,  1},  

	// When enabled, an additional register is placed at the read data out to 
	// help improve FMAX.
	parameter bit        PORT_DREG_READ    [0:15] = '{  1,  1,  1,  1,  
														1,  1,  1,  1,  
														1,  1,  1,  1,  
														1,  1,  1,  1},  

	// 1 through 256, 0=No sequential burst priority.
	// Defines the maximum consecutive read or write burst commands from a 
	// single port if another read/write port requests exists with the same 
	// priority level, but their memory request exist in a different row.  
	// * Every 1 counts for a BL8 burst. This will prevent a single continuous 
	// stream port from hogging up all the ram access time.
	// IE: If set to 0, commander will seek if other read/write requests are 
	// ready before continuing access to the same port DDR3 access.
	parameter bit [8:0]  PORT_MAX_BURST    [0:15] = '{256,256,256,256,
													  256,256,256,256,
													  256,256,256,256,
													  256,256,256,256},

	// 1=ON, 0=OFF, With SMART_BANK enabled, the BrianHG_DDR3_COMMANDER will 
	// remember which ROW# has been activated in each DDR3 BANK# so that when 
	// prioritizing read and write ports of equal priority, multiple commands 
	// across multiple banks whose ROWs have matching existing activation will 
	// be prioritized/coalesced as if they were part of the sequential burst as 
	// PRECHARGE and ACTIVATE commands are not needed when bursting between 
	// active banks maintaining an unbroken read/write stream. (Of course the 
	// BrianHG_DDR3_PHY_SEQ is able to handle smart banking as well...)
	// Note that enabling this feature uses additional logic cells and may .
	// impact FMAX. Disabling this feature will only coalesce commands in the 
	// current access ROW. Parameter 'BANK_ROW_ORDER' will define which address
	// bits define the accessed BANK number.
	parameter bit        SMART_BANK         = 0     
	)

	// Finally the module ports. These names match the ones that the demo code
	// uses, and adopts the convention used in the Gowin contraints, where
	// diff-pairs are <signal> and <signal_n>
	(
	input	wire							clk,		// clock from the board
	input	wire							rst,		// reset from the board

	output 	wire[DDR3_WIDTH_ADDR-1:0]		ddr_addr,	// Address bits
	output 	wire[DDR3_WIDTH_BANK-1:0]		ddr_bank,	// Bank-selection bits
	output	wire							ddr_cs_n,	// chip-select
	output	wire							ddr_ras_n,	// Row-address strobe
	output	wire							ddr_cas_n,	// Col-address strobe
	output	wire							ddr_we_n,	// write-enable
	output	wire							ddr_ck,  	// +ve DDR clock
	output	wire							ddr_ck_n,	// -ve DDR clock
	output	wire							ddr_cke,	// clock-enable
	output	wire							ddr_odt,	// on-die termination
	output	wire							ddr_rst_n,	// DDR reset
	output	wire[DDR3_WIDTH_DM-1:0]			ddr_dm,		// Data-lane mask

	inout	wire[DDR3_WIDTH_DQ-1:0]			ddr_dq,		// Data lanes
	inout	wire[DDR3_WIDTH_DQS-1:0]		ddr_dqs,	// +ve data-lane strobes
	inout	wire[DDR3_WIDTH_DQS-1:0]		ddr_dqs_n	// -ve data-lane strobes
	);


// *****************************************************************************
// BrianHG_DDR3_PHY_SEQ logic / wires.
// *****************************************************************************
	logic 					RST_OUT;			// PLL-is-ready reset
	logic 					PLL_LOCKED; 		// PLL is locked
	logic					DDR3_CLK;			// Main DDR3 clock
	logic 					DDR3_CLK_50;		// 50% of DDR clock
	logic					DDR3_CLK_25;		// 25% of DDR clock
	logic 					CMD_CLK;			// DDR3 command clock

	logic 					SEQ_CAL_PASS;		// Sequencer calibration passed
	logic					DDR3_READY;			// DDR3 is ready
	logic 	[7:0] 			RDCAL_data;			// Calibration data to display


// *****************************************************************************
// DDR3 controller interface.
// *****************************************************************************

	// For each port, when high, the DDR3 controller will not accept an incoming 
	// command on that port.
	logic						CMD_busy            [0:PORT_TOTAL-1];

	 // Send a command.
	logic						CMD_ena             [0:PORT_TOTAL-1];

	// Set high when you want to write data, low when you want to read data. 
	logic						CMD_write_ena       [0:PORT_TOTAL-1];

	// Command Address pointer.
	logic [PORT_ADDR_SIZE-1:0]	CMD_addr            [0:PORT_TOTAL-1];  

	// During a 'CMD_write_req', this data will be written into the DDR3 at 
	// address 'CMD_addr'. Each port's 'PORT_DATA_WIDTH' setting will prune the 
	// unused write data bits.
	// *** All channels of the 'CMD_wdata' will always be PORT_CACHE_BITS wide, 
	// however, only the bottom 'PORT_W_DATA_WIDTH' bits will be active.
	logic [PORT_CACHE_BITS-1:0]	CMD_wdata           [0:PORT_TOTAL-1];  

	// Write enable byte mask for the individual bytes within the 256 bit data 
	// bus. When low, the associated byte will not be written.
	// Each port's 'PORT_DATA_WIDTH' setting will prune the unused mask bits.
	// *** All channels of the 'CMD_wmask' will always be 'PORT_CACHE_BITS/8' 
	// wide, however, only the bottom 'PORT_W_DATA_WIDTH/8' bits will be active.
	logic [PORT_CACHE_BITS/8-1:0] CMD_wmask			[0:PORT_TOTAL-1];  

	// The contents of the 'CMD_read_vector_in' during a read req will be sent 
	// to the 'CMD_read_vector_out' in parallel with the 'CMD_read_data' during 
	// the 'CMD_read_ready' pulse.
	// *** All channels of the 'CMD_read_vector_in' will always be 
	// 'PORT_VECTOR_SIZE' wide, it is up to the user to '0' the unused input 
	// bits on each individual channel.
	logic [PORT_VECTOR_SIZE-1:0]  CMD_read_vector_in  [0:PORT_TOTAL-1];  

	// Goes high for 1 clock when the read command data is valid.
	logic                         CMD_read_ready      [0:PORT_TOTAL-1];  
	
	// Valid read data when 'CMD_read_ready' is high.
	// *** All channels of the 'CMD_read_data will' always be 'PORT_CACHE_BITS' 
	// wide, however, only the bottom 'PORT_R_DATA_WIDTH' bits will be active.
	logic [PORT_CACHE_BITS-1:0]   CMD_read_data       [0:PORT_TOTAL-1];  

	// Returns the 'CMD_read_vector_in' which was sampled during the 
	// 'CMD_read_req' in parallel with the 'CMD_read_data'.  This allows for 
	// multiple post reads where the output has a destination pointer.
	logic [PORT_VECTOR_SIZE-1:0]  CMD_read_vector_out [0:PORT_TOTAL-1];

	// Boosts the port's 'PORT_PRIORITY' parameter by a weight of 4 when set.
	logic                         CMD_priority_boost  [0:PORT_TOTAL-1];  


// *****************************************************************************
// This Write Data TAP port passes a copy of all the writes going to the DDR3 
// memory. This will allow to 'shadow' selected write addresses to other 
// peripherals which may be accessed by all the multiple write ports.
// This port is synchronous to the CMD_CLK.
// *****************************************************************************
	logic                         TAP_WRITE_ENA ;
	logic [PORT_ADDR_SIZE-1:0]    TAP_ADDR      ;
	logic [PORT_CACHE_BITS-1:0]   TAP_WDATA     ;
	logic [PORT_CACHE_BITS/8-1:0] TAP_WMASK     ;



// *****************************************************************************
// *****************************************************************************
// *****************************************************************************
// This module is the complete BrianHG_DDR3_CONTROLLER_v16 system assembled 
// initiating:
//
//   o BrianHG_DDR3_CONTROLLER_v16_top.sv
//		-> 	v1.6 TOP entry to the complete project which wires the 
//			DDR3_COMMANDER_v16 to the DDR3_PHY_SEQ giving you access to all the 
//			read/write ports + access to the DDR3 IO pins.
//   o BrianHG_DDR3_COMMANDER_v16.sv          
//		->	v1.6 High FMAX speed multi-port read and write requests and cache,
//			commands the BrianHG_DDR3_PHY_SEQ.sv sequencer.
//   o BrianHG_DDR3_CMD_SEQUENCER_v16.sv      
//		->	v1.6 Takes in the read and write requests, generates a stream of 
//			DDR3 commands to execute the read and writes. 
//   o BrianHG_DDR3_PHY_SEQ_v16.sv            
//		->	v1.6 DDR3 PHY sequencer.  (If you want just a compact DDR3 
//			controller, skip the DDR3_CONTROLLER_top & DDR3_COMMANDER and 
//			just use this module alone.) 
//   o BrianHG_DDR3_IO_PORT_ALTERA.sv         
//		->  Physical DDR IO pin driver specifically for Altera/Intel 
//			Cyclone III/IV/V and MAX10.
//   o BrianHG_DDR3_PLL.sv                    
//		-> 	Generates the system clocks. (*** Currently Altera/Intel only ***)
//   o BrianHG_DDR3_GEN_tCK.sv
//		-> 	Generates all the tCK count clock cycles for the DDR3_PHY_SEQ so 
//			that the DDR3 clock cycle requirements are met.
//   o BrianHG_DDR3_FIFOs.sv                  
//		-> 	Serial shifting logic FIFOs.
//
// *****************************************************************************
// *****************************************************************************
// *****************************************************************************
BrianHG_DDR3_CONTROLLER_v16_top #(	
						.FPGA_VENDOR			(FPGA_VENDOR),   
						.FPGA_FAMILY        	(FPGA_FAMILY),   
						.INTERFACE_SPEED    	(INTERFACE_SPEED),
						.BHG_OPTIMIZE_SPEED		(BHG_OPTIMIZE_SPEED),   
						.BHG_EXTRA_SPEED		(BHG_EXTRA_SPEED),
						.CLK_KHZ_IN				(CLK_KHZ_IN),   
						.CLK_IN_MULT        	(CLK_IN_MULT),   
						.CLK_IN_DIV         	(CLK_IN_DIV),

						.DDR3_CK_MHZ			(DDR3_CK_MHZ),   
						.DDR3_SPEED_GRADE   	(DDR3_SPEED_GRADE),   
						.DDR3_SIZE_GB       	(DDR3_SIZE_GB),
						.DDR3_WIDTH_DQ			(DDR3_WIDTH_DQ),   
						.DDR3_NUM_CHIPS     	(DDR3_NUM_CHIPS),   
						.DDR3_NUM_CK        	(DDR3_NUM_CK),
						.DDR3_WIDTH_ADDR		(DDR3_WIDTH_ADDR),   
						.DDR3_WIDTH_BANK    	(DDR3_WIDTH_BANK),   
						.DDR3_WIDTH_CAS     	(DDR3_WIDTH_CAS),
						.DDR3_WIDTH_DM			(DDR3_WIDTH_DM),   
						.DDR3_WIDTH_DQS     	(DDR3_WIDTH_DQS),   
						.DDR3_ODT_RTT       	(DDR3_ODT_RTT),
						.DDR3_RZQ				(DDR3_RZQ),   
						.DDR3_TEMP          	(DDR3_TEMP),   
						.DDR3_WDQ_PHASE     	(DDR3_WDQ_PHASE), 
						.DDR3_RDQ_PHASE			(DDR3_RDQ_PHASE),   
						.DDR3_MAX_REF_QUEUE 	(DDR3_MAX_REF_QUEUE),   
						.IDLE_TIME_uSx10    	(IDLE_TIME_uSx10),
						.SKIP_PUP_TIMER			(SKIP_PUP_TIMER),   
						.BANK_ROW_ORDER     	(BANK_ROW_ORDER),   
						.DDR_TRICK_MTPS_CAP 	(DDR_TRICK_MTPS_CAP),

						.PORT_ADDR_SIZE			(PORT_ADDR_SIZE),
						.PORT_MLAYER_WIDTH		(PORT_MLAYER_WIDTH),
						.PORT_TOTAL				(PORT_TOTAL),   
						.PORT_VECTOR_SIZE   	(PORT_VECTOR_SIZE),   
						.PORT_TOGGLE_INPUT  	(PORT_TOGGLE_INPUT),
						.PORT_R_DATA_WIDTH		(PORT_R_DATA_WIDTH),   
						.PORT_W_DATA_WIDTH  	(PORT_W_DATA_WIDTH),
						.PORT_PRIORITY			(PORT_PRIORITY),   
						.PORT_READ_STACK    	(PORT_READ_STACK),
						.PORT_CACHE_SMART		(PORT_CACHE_SMART),   
						.PORT_W_CACHE_TOUT  	(PORT_W_CACHE_TOUT),
						.PORT_R_CACHE_TOUT		(PORT_R_CACHE_TOUT),   
						.PORT_R_WDT_ENA     	(PORT_R_WDT_ENA),   
						.PORT_R_CACHE_TOUT_ENA	(PORT_R_CACHE_TOUT_ENA),
						.PORT_MAX_BURST			(PORT_MAX_BURST),   
						.PORT_DREG_READ     	(PORT_DREG_READ),   
						.SMART_BANK         	(SMART_BANK)) 
	DDR3 (

						// *** Interface Reset, Clocks & Status. ***
						.RST_IN               (RST_IN),                   
						.RST_OUT              (RST_OUT),
						.CLK_IN               (CLK_IN),                   
						.CMD_CLK              (CMD_CLK),
						.DDR3_READY           (DDR3_READY),                   
						.SEQ_CAL_PASS         (SEQ_CAL_PASS),
						.PLL_LOCKED           (PLL_LOCKED),                   
						.DDR3_CLK             (DDR3_CLK),
						.DDR3_CLK_50          (DDR3_CLK_50),                   
						.DDR3_CLK_25          (DDR3_CLK_25),

						// *** DDR3 Commander functions ***
						.CMD_busy             (CMD_busy),                    
						.CMD_ena              (CMD_ena),
						.CMD_write_ena        (CMD_write_ena),                    
						.CMD_addr             (CMD_addr),
						.CMD_wdata            (CMD_wdata),                    
						.CMD_wmask            (CMD_wmask),
						.CMD_read_vector_in   (CMD_read_vector_in),                    
						.CMD_priority_boost   (CMD_priority_boost),

						.CMD_read_ready       (CMD_read_ready),                    
						.CMD_read_data        (CMD_read_data),
						.CMD_read_vector_out  (CMD_read_vector_out),

						 // For test purposes, refresh timer / activity.
						.SEQ_refresh_hold     (1'b0),

						// *** DDR3 Ram Chip IO Pins ***           
						.DDR3_CK_p  		(DDR3_CK_p),    
						.DDR3_CK_n  		(DDR3_CK_n),     
						.DDR3_CKE     		(DDR3_CKE),     
						.DDR3_CS_n 			(DDR3_CS_n),
						.DDR3_RAS_n 		(DDR3_RAS_n),    
						.DDR3_CAS_n 		(DDR3_CAS_n),     
						.DDR3_WE_n    		(DDR3_WE_n),     
						.DDR3_ODT  			(DDR3_ODT),
						.DDR3_A     		(DDR3_A),    
						.DDR3_BA    		(DDR3_BA),     
						.DDR3_DM      		(DDR3_DM),     
						.DDR3_DQ   			(DDR3_DQ),
						.DDR3_DQS_p 		(DDR3_DQS_p),    
						.DDR3_DQS_n 		(DDR3_DQS_n),     
						.DDR3_RESET_n 		(DDR3_RESET_n),

						// debug IO
						.RDCAL_data 		(RDCAL_data),    
//						.reset_phy 			(DB232_rx3[7]),     
//						.reset_cmd    		(DB232_rx3[6]),

						// Write data TAP port.
						.TAP_WRITE_ENA 		(TAP_WRITE_ENA), 
						.TAP_ADDR      		(TAP_ADDR),
						.TAP_WDATA     		(TAP_WDATA), 
						.TAP_WMASK     		(TAP_WMASK));

// *****************************************************************************
// *****************************************************************************
// *****************************************************************************

endmodule

