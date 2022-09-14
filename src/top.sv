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
	parameter int        CLK_IN_MULT             = 22,               
	
	// Divide factor.  When CLK_KHZ_IN is 25k,50k,75k,100k,125k,150k, 
	// use (correspondingly) 2,4,6,8,10,12.
	parameter int        CLK_IN_DIV              = 2,
	
	// 0=off, Set a false PLL DDR data rate for the compiler to allow FPGA 
	// overclocking.  ***DO NOT USE.
	parameter int        DDR_TRICK_MTPS_CAP      = 0,              

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
	parameter int        DDR3_ODT_RTT            = 120,

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
	parameter bit        USE_TOGGLE_OUTPUTS    	= 1  
	)
	// And the module ports. These names match the ones that the demo code
	// uses, and adopts the convention used in the Gowin contraints, where
	// diff-pairs are <signal> and <signal_n>
	(
	input	wire							clk,		// clock from the board

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
	inout	wire[DDR3_WIDTH_DQS-1:0]		ddr_dqs_n,	// -ve data-lane strobes
	
	output	logic[7:0]						led,		// LED array
	inout	logic							uart_txd,	// UART transmit
	inout	logic							uart_rxd 	// UART receive
	);

// *****************************************************************************
// ********* BrianHG_DDR3_PHY_SEQ logic / wires.
// *****************************************************************************
	logic 							CLK_IN;				// External clock
	logic 							RESET; 				// Reset post PLL-locked
	logic 							PLL_LOCKED;			// PLL is locked
	logic 							DDR3_CLK;			// Main DDR3 clock
	logic							DDR3_CLK_50;		// 50% of DDR3 clock
	logic							DDR3_CLK_25;		// 25% of DDR3 clock
	logic							DDR3_CLK_DQS;		// DQ strobe clock
	logic							DDR3_CLK_RDQ;		// DDR3 read DQ clock
	logic 							DDR3_CLK_WDQ;		// DDR3 write DW clock
	logic 							CMD_CLK;			// Command clock

	logic                         	SEQ_CMD_ENA_t;		// Sequencer EN (toggle)
	logic                         	SEQ_WRITE_ENA;		// Sequencer write-enable
	logic [PORT_ADDR_SIZE-1:0]    	SEQ_ADDR;			// Sequencer address
	logic [DDR3_RWDQ_BITS-1:0]    	SEQ_WDATA,WDATA;	// Write-data
	logic [DDR3_RWDQ_BITS/8-1:0]  	SEQ_WMASK,WMASK;	// Write mask

	// Embed multiple read request returns into the SEQ_RDATA_VECT_IN.
	logic [DDR3_VECTOR_SIZE-1:0]  	SEQ_RDATA_VECT_IN;  
	logic                         	SEQ_refresh_hold;

	logic                         	SEQ_BUSY_t;			// Still busy
	logic                         	SEQ_RDATA_RDY_t;	// Ready to read
	logic [DDR3_RWDQ_BITS-1:0]    	SEQ_RDATA;			// Read data
	logic [DDR3_VECTOR_SIZE-1:0]  	SEQ_RDATA_VECT_OUT;	// ?
	logic [4:0]                   	SEQ_refresh_queue;	// ?

	logic                         	SEQ_CAL_PASS;		// Calibration pass
	logic                         	DDR3_READY;			// Rock'n'roll!

	logic                         	phase_step;			// Increment phase	
	logic 							phase_updn;			// Increment direction
	logic                         	phase_done;			// Phase done
	logic [7:0]                   	RDCAL_data;			// Calibration data		

	assign SEQ_refresh_hold = 0 ;


// *****************************************************************
// ********* Assign BrianHG_DDR3_PHY_SEQ logic / wires to Gowin IOs.
// *****************************************************************

	// Maximum = 20, IE 15 seconds to transfer the entire 1 mgeabyte by RS232...
	localparam   RS232_MEM_ADR_SIZE = 24 ; 

	logic                          RS232_RST_OUT  ;
	logic                          RS232_RXD      ;
	logic                          RS232_TXD      ;
	logic                          RS232_TXD_LED  ;
	logic                          RS232_RXD_LED  ;
	logic                          DB232_rreq              ;
	// The DB232_rrdy_t is for monitoring the toggle output.
	logic                          DB232_rrdy,DB232_rrdy_t ; 
	logic                          DB232_wreq        ;
	logic [RS232_MEM_ADR_SIZE-1:0] DB232_addr        ;
	logic [7:0]                    DB232_wdat        ;
	logic [7:0]                    DB232_rdat        ;
	logic [7:0]                    DB232_tx0         ;
	logic [7:0]                    DB232_tx1         ;
	logic [7:0]                    DB232_tx2         ;
	logic [7:0]                    DB232_tx3         ;
	logic [7:0]                    DB232_rx0         ;
	logic [7:0]                    DB232_rx1         ;
	logic [7:0]                    DB232_rx2         ;
	logic [7:0]                    DB232_rx3         ;

	logic        DB232_rreq_t ;
	logic        DB232_req ;

	logic [15:0] cnt_read = 0;

	assign CLK_IN = clk;			// Assign the reference 27MHz pll.

	assign uart_txd = RS232_TXD;	// Assign the RS232 debugger TXD output pin.
	assign uart_rxd = 1'bz;			// Make this IO into a tri-state input.
	assign RS232_RXD  = uart_rxd;   // Assign the RS232 debugger RXD input pin.

	logic        SEQ_RDATA_RDY_t_dly;

// *****************************************************************************
// This module generates the master reference clocks for the memory system.
// *****************************************************************************
	BrianHG_DDR3_PLL  			  #(.FPGA_VENDOR    	(FPGA_VENDOR),    
									.INTERFACE_SPEED 	(INTERFACE_SPEED),  
									.DDR_TRICK_MTPS_CAP	(DDR_TRICK_MTPS_CAP),
									.CLK_KHZ_IN     	(CLK_KHZ_IN),     
									.CLK_IN_MULT     	(CLK_IN_MULT),      
									.CLK_IN_DIV			(CLK_IN_DIV),
									.DDR3_WDQ_PHASE 	(DDR3_WDQ_PHASE), 
									.DDR3_RDQ_PHASE  	(DDR3_RDQ_PHASE),   
									.FPGA_FAMILY		(FPGA_FAMILY)) 
		BHG_DDR3_PLL (
									.RST_IN         	(RS232_RST_OUT),  
									.RST_OUT         	(RESET),            
									.CLK_IN    			(CLK_IN),      
									.DDR3_CLK   		(DDR3_CLK),
									.DDR3_CLK_WDQ   	(DDR3_CLK_WDQ),   
									.DDR3_CLK_RDQ    	(DDR3_CLK_RDQ),     
									.CMD_CLK   			(CMD_CLK),     
									.PLL_LOCKED 		(PLL_LOCKED),
									.DDR3_CLK_50    	(DDR3_CLK_50),    
									.DDR3_CLK_25     	(DDR3_CLK_25),

									.phase_step     	(phase_step),   
									.phase_updn      	(phase_updn),
									.phase_sclk     	(DDR3_CLK_25),  
									.phase_done     	(phase_done));



// *****************************************************************************
// This module receives the commands from the multi-port ram controller and 
// sequences the DDR3 IO pins.
// *****************************************************************************
	BrianHG_DDR3_PHY_SEQ_v16 	  #(.FPGA_VENDOR		(FPGA_VENDOR),
									.FPGA_FAMILY		(FPGA_FAMILY),
									.INTERFACE_SPEED	(INTERFACE_SPEED),
									.BHG_OPTIMIZE_SPEED	(BHG_OPTIMIZE_SPEED),
									.BHG_EXTRA_SPEED	(BHG_EXTRA_SPEED),
									.CLK_KHZ_IN			(CLK_KHZ_IN),
									.CLK_IN_MULT		(CLK_IN_MULT),
									.CLK_IN_DIV			(CLK_IN_DIV),
							
									.DDR3_CK_MHZ		(DDR3_CK_MHZ ),
									.DDR3_SPEED_GRADE	(DDR3_SPEED_GRADE),
									.DDR3_SIZE_GB		(DDR3_SIZE_GB),
									.DDR3_WIDTH_DQ		(DDR3_WIDTH_DQ),
									.DDR3_NUM_CHIPS		(DDR3_NUM_CHIPS),
									.DDR3_NUM_CK		(DDR3_NUM_CK),
									.DDR3_WIDTH_ADDR	(DDR3_WIDTH_ADDR),
									.DDR3_WIDTH_BANK	(DDR3_WIDTH_BANK),
									.DDR3_WIDTH_CAS		(DDR3_WIDTH_CAS),
									.DDR3_WIDTH_DM		(DDR3_WIDTH_DM),
									.DDR3_WIDTH_DQS		(DDR3_WIDTH_DQS),
									.DDR3_ODT_RTT		(DDR3_ODT_RTT),
									.DDR3_RZQ			(DDR3_RZQ),
									.DDR3_TEMP			(DDR3_TEMP),
									.DDR3_WDQ_PHASE		(DDR3_WDQ_PHASE), 
									.DDR3_RDQ_PHASE		(DDR3_RDQ_PHASE),
									.DDR3_MAX_REF_QUEUE	(DDR3_MAX_REF_QUEUE),
									.IDLE_TIME_uSx10	(IDLE_TIME_uSx10),
									.SKIP_PUP_TIMER		(SKIP_PUP_TIMER),
									.BANK_ROW_ORDER		(BANK_ROW_ORDER),

									// only use in half speed mode.
									.USE_TOGGLE_CONTROLS(USE_TOGGLE_OUTPUTS), 

									.PORT_VECTOR_SIZE	(DDR3_VECTOR_SIZE),
									.PORT_ADDR_SIZE		(PORT_ADDR_SIZE)) 
		
		DDR3_PHY (              	// *** DDR3_PHY_SEQ Clocks & Reset ***
									.RST_IN				(RESET || DB232_rx3[7]),
									.DDR_CLK       		(DDR3_CLK),
									.DDR_CLK_WDQ  		(DDR3_CLK_WDQ),
									.DDR_CLK_RDQ 		(DDR3_CLK_RDQ),
									.CLK_IN				(CLK_IN),
									.DDR_CLK_50			(DDR3_CLK_50),
									.DDR_CLK_25			(DDR3_CLK_25),

									// *** DDR3 Ram Chip IO Pins ***           
									.DDR3_RESET_n		(ddr_rst_n),
									.DDR3_CK_p			(ddr_ck),
									.DDR3_CKE			(ddr_cke),     
									.DDR3_CS_n   		(ddr_cs_n),
									.DDR3_RAS_n			(ddr_ras_n),
									.DDR3_CAS_n			(ddr_cas_n),  
									.DDR3_WE_n 			(ddr_we_n),
									.DDR3_ODT			(ddr_odt),
									.DDR3_A				(ddr_addr),
									.DDR3_BA			(ddr_bank),
									.DDR3_DM 			(ddr_dm),
									.DDR3_DQ			(ddr_dq),
									.DDR3_DQS_p			(ddr_dqs),
									.DDR3_DQS_n			(ddr_dqs_n),
									.DDR3_CK_n 			(ddr_ck_n),

									// *** Command port input ***              
									.CMD_CLK			(CMD_CLK),
									.SEQ_CMD_ENA_t 		(SEQ_CMD_ENA_t),
									.SEQ_WRITE_ENA      (SEQ_WRITE_ENA),
									.SEQ_ADDR			(SEQ_ADDR),
									.SEQ_WDATA			(SEQ_WDATA),
									.SEQ_WMASK			(SEQ_WMASK),
									.SEQ_RDATA_VECT_IN	(SEQ_RDATA_VECT_IN),                                        
									.SEQ_refresh_hold	(SEQ_refresh_hold),

									// *** Command port results ***                                                 
									.SEQ_BUSY_t			(SEQ_BUSY_t),
									.SEQ_RDATA_RDY_t	(SEQ_RDATA_RDY_t),
									.SEQ_RDATA			(SEQ_RDATA),
									.SEQ_RDATA_VECT_OUT	(SEQ_RDATA_VECT_OUT),
									.SEQ_refresh_queue	(SEQ_refresh_queue),

									// *** Diagnostic flags ***                                                 
									.SEQ_CAL_PASS		(SEQ_CAL_PASS),
									.DDR3_READY			(DDR3_READY),

									// *** PLL tuning controls ***
									.phase_done			(phase_done),
									.phase_step			(phase_step),
									.phase_updn         (phase_updn),
									.RDCAL_data			(RDCAL_data));

// *****************************************************************************




// *****************************************************************************
// Using the lower bits of the write address, convert a write byte to the 
// 128bit bus with the correct byte mask write enable.
// *****************************************************************************
    DDR3_CMD_ENCODE_BYTE 
        #(
         .addr_size        ( 5              ),    // width of the address input
         .input_width      ( 8              ),    // width of the input data
         .output_width     ( DDR3_RWDQ_BITS ))    // width of the output data

    // Take the byte write address and generate a positioned write data & 
    // mask output. 
    DDR3_CMD_ENCODE_BYTE_inst (
         .addr             ( DB232_addr[4:0]),    
         .data_in          ( DB232_wdat     ),
         .mask_in          ( 1'b1           ),
         .data_out         ( WDATA          ),
         .mask_out         ( WMASK          ) );

// *****************************************************************************
// Take the 128bit read data and return the selected single byte using the lower
// address bits stored in the returned read vector
// *****************************************************************************
    DDR3_CMD_DECODE_BYTE 
        #(
         .addr_size    (5             ),           // width of the address input
         .input_width  (DDR3_RWDQ_BITS),           // width of the input data
         .output_width (8             ))           // width of the output data

    DDR3_CMD_DECODE_BYTE_inst (
         // Use the read data vector as a pointer to which byte was 
         // selected in the read.
         .addr         (SEQ_RDATA_VECT_OUT[4:0] ), 
         .data_in      (SEQ_RDATA               ), // the 128bit read data.
         .data_out     (DB232_rdat              ));// Output the selected byte.


// *****************************************************************************
// Pass the RS232 debugger commands to and from the DDR3_PHY_SEQ module.
// *****************************************************************************
    localparam RS232_TOP   = RS232_MEM_ADR_SIZE-1;
    always_ff @(posedge DDR3_CLK_25) begin 
        if (RESET) 
            begin
                SEQ_CMD_ENA_t                   <= 0 ;
                SEQ_WRITE_ENA                   <= 0 ;
                SEQ_ADDR [3:0]                  <= 0 ;
                SEQ_ADDR [19:4]                 <= 0 ;
                SEQ_ADDR [PORT_ADDR_SIZE-1:20]  <= 0 ;
                SEQ_RDATA_VECT_IN               <= {DDR3_VECTOR_SIZE{1'b0}} ;
                SEQ_RDATA_RDY_t_dly             <= SEQ_RDATA_RDY_t;
                cnt_read                        <= 0 ;
                DB232_req                       <= 0 ;

            end 
        else 
            begin
                if (DB232_rreq || DB232_wreq) 
                    begin                                    
                        // Send out a RS232 request.
                        SEQ_WRITE_ENA           <= DB232_wreq;
                        SEQ_ADDR [3:0]          <= 4'b0000; 
                        SEQ_ADDR [RS232_TOP:4]  <= DB232_addr[RS232_TOP-1:4];

                        // When performing a read request, set which byte in the 
                        // 128 bit result should be sent to the RS232 Debugger.
                        SEQ_RDATA_VECT_IN       <= DB232_addr[4:0] ; 
                        SEQ_WDATA               <= WDATA;
                        SEQ_WMASK               <= WMASK;

                        DB232_req               <= !DB232_req ;
                    end

                // When not busy, pass the DDR3 requests delayed by 1 clock 
                // improving meta-stability when crossing clock domains.
                if (SEQ_BUSY_t==SEQ_CMD_ENA_t) 
                    SEQ_CMD_ENA_t   <= DB232_req ; 

                SEQ_RDATA_RDY_t_dly  <= SEQ_RDATA_RDY_t ;
                DB232_rrdy_t         <= SEQ_RDATA_RDY_t_dly  ;

                // Delayed after 2 clocks, if a SEQ_RDATA_RDY_t came in, tell
                // the RS232 debugger that the read byte came in.
                DB232_rrdy           <= SEQ_RDATA_RDY_t_dly != DB232_rrdy_t ; 

                // increment the read counter.
                if (DB232_rrdy) 
                    cnt_read <= cnt_read + 1'b1 ;                

            end // !reset

        DB232_tx3[7:0] <= RDCAL_data[7:0] ; // Send out read calibration data.
        DB232_tx1[7:0] <= cnt_read[7:0] ;
        DB232_tx2[7:0] <= cnt_read[15:8]   ;

    end // @CLK_IN


    // Show LEDs and send them to one of the RD232 debugger display ports.
    always_ff @(posedge DDR3_CLK_25) 
        // Make sure the signals driving LED's aren't route optimized for the 
        // LED's IO pin location.
        begin         
            DB232_tx0[0]   <= RS232_TXD_LED ;     // RS232 Debugger TXD LED
            DB232_tx0[1]   <= 1'b0 ;              // Turn off LED.
            DB232_tx0[2]   <= PLL_LOCKED   ;
            DB232_tx0[3]   <= SEQ_CAL_PASS ;              // Turn off LED.
            DB232_tx0[4]   <= DDR3_READY ;
            DB232_tx0[5]   <= 1'b0 ;
            DB232_tx0[6]   <= 1'b0 ;              // Turn off LED.
            DB232_tx0[7]   <= RS232_RXD_LED ;     // RS232 Debugger RXD LED

            // Pass the calibration data to the LEDs.
            led            <= 8'hff ^ RDCAL_data 
                            ^  8'((RS232_TXD_LED || RS232_RXD_LED)<<7); 
        end


// *****************************************************************************
// This module is a test RS232 bridge which uses BrianHG's RS232_Debugger.exe 
// Windows app.
// *****************************************************************************
    rs232_debugger 
        #(
        .CLK_IN_HZ(CLK_KHZ_IN*CLK_IN_MULT/CLK_IN_DIV*250), 
        .BAUD_RATE(921600), 
        .ADDR_SIZE(RS232_MEM_ADR_SIZE), 
        .READ_REQ_1CLK(1)
        ) 
    rs232_debug 
        (
        // System clock.  Recommend at least 20MHz for the 921600 baud rate.
        .clk         ( DDR3_CLK_25   ),    
        
        // When sent by the PC RS232_Debugger utility this outputs a high 
        // signal for 8 clock cycles.
        .cmd_rst     ( RS232_RST_OUT ),    

        // Connect this to the RS232 RXD input pin.
        .rxd         ( RS232_RXD     ),    
        
        // Connect this to the RS232 TXD output pin.
        .txd         ( RS232_TXD     ),    
        
        // Optionally wire this to a LED it will go high whenever the RS232 
        //TXD is active.
        .LED_txd     ( RS232_TXD_LED ), 

        // Optionally wire this to a LED it will go high whenever the RS232 
        // RXD is active.
        .LED_rxd     ( RS232_RXD_LED ),

        // This output will pulse high for 1 clock when a read request is 
        // taking place.
        .host_rd_req ( DB232_rreq    ),

        // This input should be set high once the 'host_rdata[7:0]' input 
        // contains valid data.
        .host_rd_rdy ( DB232_rrdy    ),   
 
        // This output will pulse high for 1 clock when a write request 
        // is taking place.
       .host_wr_ena ( DB232_wreq    ),    
        
        // This output contains the requested read and write address.
        .host_addr   ( DB232_addr    ),    
        
        // This output contains the source RS232 8bit data to be written.
        .host_wdata  ( DB232_wdat    ),    
        
        // This input receives the 8 bit ram data to be sent to the RS232.
        .host_rdata  ( DB232_rdat    ),    
        .in0         ( DB232_tx0     ),
        .in1         ( DB232_tx1     ),
        .in2         ( DB232_tx2     ),
        .in3         ( DB232_tx3     ),
        .out0        ( DB232_rx0     ),
        .out1        ( DB232_rx1     ),
        .out2        ( DB232_rx2     ),
        .out3        ( DB232_rx3     )  );


endmodule



// *****************************************************************************
// This module takes in the write data and mask of smaller or equal input 
// PORT_W_DATA_WIDTH, then outputs the data to the correct position within 
// the data bus with the PORT_CACHE_BITS width.
// *****************************************************************************

module DDR3_CMD_ENCODE_BYTE 
    #(
    // width of the address input.
    parameter  int addr_size        = 20,  

    // width of the input data and byte mask data (mask size=/8).
    parameter  int input_width      = 8,    
    
    // width of the output data and mask data (mask size=/8)
    parameter  int output_width     = 128   
    )
    (
    input logic  [addr_size-1:0]      addr,

    // Remember, even though only the 'input_width' LSBs are functional, the 
    // port still has the full width. Upper unused bits will be ignored
    input logic  [output_width-1:0]   data_in,  
    input logic  [output_width/8-1:0] mask_in, 

    output logic [output_width-1:0]   data_out,
    output logic [output_width/8-1:0] mask_out
    );

    // Describes the number of address bits required to point to each word.
    localparam   index_width  = $clog2(output_width/8) ;    

    // The index pointer from the address.
    logic       [index_width-1:0]     index_ptr ;          

    always_comb begin

        // Retrieve the index position.
        // Filter out the least significant address bits when the input width is
        // greater than 8 bits.
        index_ptr = (index_width)'((addr[index_width-1:0] ^ {index_width{1'b1}}) 
                                  &  ({index_width{1'b1}} ^ (input_width/8-1)));

        // Select the sole mask bits used when writing the data into the 
        // appropriate 8 bit segments of data_out.
        mask_out  = (output_width/8)'(mask_in[input_width/8-1:0]<<index_ptr);

        // Copy the smaller input width data across the larger output data bus.
        for (int i=0 ; i < output_width ; i+=input_width) 
            data_out[i +: input_width] = data_in[0 +: input_width] ;

    end // always comb

endmodule


// *****************************************************************************
// This module takes in the full PORT_CACHE_BITS width read data and outputs a 
// smaller or equal data at the size of PORT_R_DATA_WIDTH.
// *****************************************************************************
module DDR3_CMD_DECODE_BYTE 
    #(
    parameter  int addr_size    = 20,           //  of the address input.
    parameter  int input_width  = 128,          //  of the input data.
    parameter  int output_width = 8             //  of the output data.
    )
    (
    input logic  [addr_size-1:0]      addr,
    input logic  [input_width-1:0]    data_in,

    // **** REMEMBER, the output bus is still the same full PORT_CACHE_BITS, 
    // it's just that the unused bits will be set to 0
    output logic [input_width-1:0]    data_out  
    );

    // Describes the number of address bits required to point to each word.
    localparam   index_width  = $clog2(input_width/8) ;    

    // The index pointer from the address.
    logic       [index_width-1:0]     index_ptr ;          

    always_comb begin

        // Retrieve the index position.
        // Filter out the least significant address bits when the output 
        // width is greater than 8 bits.
        index_ptr  = (index_width)'((addr[index_width-1:0] ^ {index_width{1'b1}}) 
                                   &({index_width{1'b1}} ^ (output_width/8-1))) ; 

        // Select the data out word based on the index position
        data_out   = (data_in >> (index_ptr * 8)) & {output_width{1'b1}} ;

    end // always comb

endmodule

