// *********************************************************************
//
// BrianHG_DDR3_IO_PORT_ALTERA.sv DDR Port
//
// Version 1.50, November 28, 2021.
//               Added *preserve* and duplicate logic to minimize fanouts to help FMAX.
// Optimized the RDQ_SYNC_CHAIN, WDQ_SYNC_CHAIN and new CMD_ADD_DLY for the best FMAX upwards of 450MHz.
//
//
// Connects to the DDR3.
// Shifts out the write from the write buffer.
// Shifts in the read to the read buffer.
//
// Written by Brian Guralnick.
// For public use.
// Leave questions in the https://www.eevblog.com/forum/fpga/brianhg_ddr3_controller-open-source-ddr3-controller/
//
// *********************************************************************
//
//

`timescale 1 ps/ 1 ps // 1 picosecond steps, 1 picosecond precision.

module DDR3_IO_PORT_GOWIN #(

parameter string     FPGA_VENDOR             = "Gowin ",         // Use ALTERA, INTEL, GOWIN, LATTICE or XILINX.
parameter string     FPGA_FAMILY             = "GW2A-18",        // With Gowin, use GW2A-18, GW2A-55

parameter bit        BHG_EXTRA_SPEED         = 1,                // Use '1' for even better FMAX performance or when overclocking the core.  This will increase logic cell usage.

// ****************  System clock generation and operation.

parameter int        CLK_KHZ_IN              = 50000,            // PLL source input clock frequency in KHz.
parameter int        CLK_IN_MULT             = 32,               // Multiply factor to generate the DDR MTPS speed divided by 2.
parameter int        CLK_IN_DIV              = 4,                // Divide factor.  When CLK_KHZ_IN is 25000,50000,75000,100000,125000,150000, use 2,4,6,8,10,12.

parameter int        DDR3_WDQ_PHASE          = 270,              // 270,  Select the write and write DQS output clock phase relative to the DDR3_CLK/
parameter int        DDR3_RDQ_PHASE          = 0,                // 0,    Select the read latch clock for the read data and DQS input relative to the DDR3_CLK.


parameter int        DDR3_WIDTH_DQ           = 16,               // Use 8 or 16.  The width of each DDR3 ram chip.
parameter int        DDR3_NUM_CHIPS          = 1,                // 1, 2, or 4 for the number of DDR3 RAM chips.

parameter int        DDR3_NUM_CK             = (DDR3_NUM_CHIPS), // Select the number of DDR3_CLK & DDR3_CLK# output pairs.  Add 1 for every DDR3 Ram chip.
                                                                 // These are placed on a DDR DQ or DDR CK# IO output pins.

parameter int        DDR3_WIDTH_ADDR         = 15,               // Use for the number of bits to address each row.
parameter int        DDR3_WIDTH_BANK         = 3,                // Use for the number of bits to address each bank.
parameter int        DDR3_WIDTH_CAS          = 10,               // Use for the number of bits to address each column.

parameter int        DDR3_WIDTH_DM           = (DDR3_WIDTH_DQ*DDR3_NUM_CHIPS/8), // The width of the byte write data mask.
parameter int        DDR3_WIDTH_DQS          = (DDR3_WIDTH_DQ*DDR3_NUM_CHIPS/8), // The number of DQS pairs.
parameter int        DDR3_RWDQ_BITS          = (DDR3_WIDTH_DQ*DDR3_NUM_CHIPS*8), // Must equal to total bus width across all DDR3 ram chips *8.


parameter bit        WDQ_CLK_270             = (DDR3_WDQ_PHASE>=180), // When enabled, the expected phase of the DDR_CLK_WDQ will be 270 degrees instead of 90 degrees.
                                                                      // When using, please set WDQ_OE_ENABLE_EARLY=1 & WDQ_OE_DISABLE_LATE=0.

parameter bit        WDQ_OE_ENABLE_EARLY     = 1,                     // When enabled, the DQ write OE will begin 1 extra DDR3_CLK clock early.
parameter bit        WDQ_OE_DISABLE_LATE     = (DDR3_WDQ_PHASE<180),  // When enabled, the DQ write OE will end 1 extra DDR3_CLK clock late.

parameter int        RDQ_ENABLE_EARLY        = 1,                // (*** Do not use***) When enabled, the allowed read data window will begin 1 DDR3_CLK clock early.
parameter int        RDQ_DISABLE_LATE        = 1,                // When enabled, the allowed read data window will end 1 extra DDR3_CLK clock late.
                                                                 // When simulating above 500MHz/1GTPS, this needs to be set to 0.

parameter bit        CMD_ADD_DLY             = 0,                // ****************** Use 0 to minimize Logic Cell / LUT count. ***************************
                                                                 // Add 1 DDR_CK extra delay in the DDR output command pipe to help FMAX

parameter int        RDQ_SYNC_CHAIN          = CMD_ADD_DLY,      // ****************** Use 0 to minimize Logic Cell / LUT count. ***************************
                                                                 // Adds # of FIFO logic cell steps in the DDR input to help increase FMAX for the DDR_CLK_RDQ domain and crossing to the DDR_CK domain.

parameter int        WDQ_SYNC_CHAIN          = 3 + CMD_ADD_DLY - WDQ_CLK_270, // + ((CLK_KHZ_IN*CLK_IN_MULT/CLK_IN_DIV)>=450000),  
                                                                 // MAXIMUM & Optimum = 4 + CMD_ADD_DLY - WDQ_CLK_270 + ((CLK_KHZ_IN*CLK_IN_MULT/CLK_IN_DIV)>=450000),
                                                                 // Shifts the position of the clock transition from DDR_CLK to DDR_CLK_WDQ of the write data FIFO path to the DQ pins.


parameter bit        DDR3_CLK_INV            = 0,                // When enabled, the DDR3_CLK will be shifted by 180 degrees.
parameter bit        DDR3_RDQS_INV           = 0                 // When enabled, the input read DQS clock pattern will be inverted.
)(
// *** Reset and Clocks
input                                RST_IN,                     // Active high reset input.

input                                DDR_CLK,                    // DDR3 clock running at 1/2 the DQ rate.
input                                DDR_CLK_WDQ,                // DDR3 phase adjustable DQS clock running at 1/2 the DQ rate.
input                                DDR_CLK_RDQ,                // DDR3 data read clock 90 degree out of phase running at 1/2 the DQ rate.

// *** DDR3 Command bus.
input                                RESET_n,
input                                CKE,    
input                                CS_n,   
input                                RAS_n,  
input                                CAS_n,  
input                                WE_n,   
input                                ODT,   
input        [DDR3_WIDTH_ADDR-1:0]   A,      
input        [DDR3_WIDTH_BANK-1:0]   BA,     
input                                WRITE,READ,

// *** Write DDR3 data
input        [DDR3_RWDQ_BITS-1:0]    WDATA,               // Write data and optional read vector buffer.
input        [DDR3_RWDQ_BITS/8-1:0]  WMASK,               // Write data mask.

// *** Read DDR3 data
output logic                         RDATA_toggle    /*= 0*/, // Read data toggle increment.
(*preserve*) output logic            RDATA_store     /*= 0*/, // Read data status, 1=good, 0=error.
output logic [DDR3_RWDQ_BITS-1:0]    RDATA           /*= 0*/, // Read data return.

// *** DDR3 IO Pins
// *** Forcing the use of an IO's flipflop to improve timing performance: (Typically needed for the NON-'altddio_bidir' IO pins.)
// *** https://www.intel.com/content/www/us/en/programmable/quartushelp/17.0/hdl/vlog/vlog_file_dir_use.htm
// ***
output                               DDR3_RESET_n, // DDR3 RESET# input pin.
output       [DDR3_NUM_CK-1:0]       DDR3_CK_p,    // DDR3_CLK ****************** YOU MUST SET THIS IO TO A DIFFERENTIAL LVDS or LVDS_E_3R
output       [DDR3_NUM_CK-1:0]       DDR3_CK_n,    // DDR3_CLK ****************** YOU MUST SET THIS IO TO A DIFFERENTIAL LVDS or LVDS_E_3R
                                                   // ************************** port to generate the negative DDR3_CLK# output.
                                                   // ************************** Generate an additional DDR_CK_p pair for every DDR3 ram chip.
output                               DDR3_CKE,     // DDR3 CKE

output                               DDR3_CS_n,    // DDR3 CS#
output                               DDR3_RAS_n,   // DDR3 RAS#
output                               DDR3_CAS_n,   // DDR3 CAS#
output                               DDR3_WE_n,    // DDR3 WE#
output                               DDR3_ODT,     // DDR3 ODT
output       [DDR3_WIDTH_ADDR-1:0]   DDR3_A,       // DDR3 multiplexed address input bus
output       [DDR3_WIDTH_BANK-1:0]   DDR3_BA,      // DDR3 Bank select

inout        [DDR3_WIDTH_DM-1:0]     DDR3_DM,      // DDR3 Write data mask. DDR3_DM[0] drives write DQ[7:0], DDR3_DM[1] drives write DQ[15:8]...
                                                   // ***  on x8 devices, the TDQS is not used and should be connected to GND or an IO set to GND.
inout        [DDR3_WIDTH_DQ-1:0]     DDR3_DQ,      // DDR3 DQ data IO bus.

inout        [DDR3_WIDTH_DQS-1:0]    DDR3_DQS_p,   // DDR3 DQS ********* IOs. DQS[0] drives DQ[7:0], DQS[1] drives DQ[15:8], DQS[2] drives DQ[23:16]...
inout        [DDR3_WIDTH_DQS-1:0]    DDR3_DQS_n,   // DDR3 DQS ********* IOs. DQS[0] drives DQ[7:0], DQS[1] drives DQ[15:8], DQS[2] drives DQ[23:16]...
                                                   // ****************** YOU MUST SET THIS IO TO A DIFFERENTIAL LVDS or LVDS_E_3R
                                                   // ****************** port to generate the negative DDR3_DQS# IO.

input logic [5:0] ODTLon, ODTLoff, CWL, CL
);

localparam DQ_WIDTH              = DDR3_WIDTH_DQ*DDR3_NUM_CHIPS;
localparam DQM_WIDTH             = DDR3_WIDTH_DQ/8*DDR3_NUM_CHIPS;

assign DDR3_RESET_n    = RESET_n  ;  // Driven by the CLK_IN clock domain, sub 10MHz signal.
assign DDR3_CKE        = CKE      ;  // Driven by the CLK_IN clock domain, sub 10MHz signal.

// Detect if this is a Gowin device we're targeting. Yes, right now this entire file is dedicated to Gowin, 
// but it may change in future
localparam GOWIN_ENABLE      = (FPGA_VENDOR[0] == "G" || FPGA_VENDOR[0] == "g") ? 1 : 0;

// For Gowin: Cope with both GW2A-18 and GW2A-55 (same architecture)
localparam GOWIN_READ_OFFSET = GOWIN_ENABLE * ((FPGA_FAMILY == "GW2A-18") ? 3 : 0);

localparam          DDR_OUT_LATENCY  = 1 - CMD_ADD_DLY ; // *** -1 counts for Altera's DDR output buffer clock latency cycles + another 2 for this core's internal latch system.
localparam          DQS_WIDTH        = 6 ;
localparam          WDQ_OE_WIDTH     = 4 + WDQ_OE_ENABLE_EARLY + WDQ_OE_DISABLE_LATE ;


logic      [21:0]   OE_DQS_PIPE  = 0 ;                // Internally generated on write command.
logic      [21:0]   WDQ_OE_PIPE  = 0 ;                // Internally generated on write command.
logic      [5:0]    DQS_POS,WDQ_OE_POS,WDQ_OUT_POS;

(*preserve*) logic [DDR3_WIDTH_DQS-1:0] OE_DQS=0,OE_DQSp=0,OE_DQSp2=0;   // The (*preserve*) is needed, otherwise, since the logic for each output enable DQS is a duplicate
                                                              // and the compiler simplifies the logic down to a single logic cell and the timing of that 1 cell
                                                              // feeding the OE for each 8 bit bank doesn't make it across all the FPGA's IOs in time to
                                                              // to achieve a peak possible FMAX.


always_comb DQS_POS      = 6'(DQS_WIDTH-2  + CWL - DDR_OUT_LATENCY) ;
always_comb WDQ_OE_POS   = 6'(WDQ_OE_WIDTH + CWL - DDR_OUT_LATENCY) ;   
always_comb WDQ_OUT_POS  = 6'(    4        + CWL - DDR_OUT_LATENCY) ;

localparam bit [DQM_WIDTH-1:0] M = {DQM_WIDTH{1'b1}};

// The (*preserve*) prevents Quartus from upgrading these registers to 'alt-shift-taps' or 'alt-syncram' core memory which are too slow for 300MHz. 
// These registers must remain in logic, not to be automatically moved to core memory blocks.

(*preserve*) logic      [DQ_WIDTH-1:0]  WDATA_PIPE_h     [0:15]             ; // Allocate enough registers for the write data pipe, unused registers will
(*preserve*) logic      [DQM_WIDTH-1:0] WMASK_PIPE_h     [0:15]             ; // be automatically pruned by the compiler.
(*preserve*) logic      [DQ_WIDTH-1:0]  WDATA_PIPE_l     [0:15]             ; // Allocate enough registers for the write data pipe, unused registers will
(*preserve*) logic      [DQM_WIDTH-1:0] WMASK_PIPE_l     [0:15]             ; // be automatically pruned by the compiler.
(*preserve*) logic      [DQ_WIDTH-1:0]  PIN_WDATA_PIPE_h [0:WDQ_SYNC_CHAIN] ; // Intermediate shift regs for clock domain boundary crossing.
(*preserve*) logic      [DQM_WIDTH-1:0] PIN_WMASK_PIPE_h [0:WDQ_SYNC_CHAIN] ; // Intermediate shift regs for clock domain boundary crossing.
(*preserve*) logic      [DQ_WIDTH-1:0]  PIN_WDATA_PIPE_l [0:WDQ_SYNC_CHAIN] ; // Intermediate shift regs for clock domain boundary crossing.
(*preserve*) logic      [DQM_WIDTH-1:0] PIN_WMASK_PIPE_l [0:WDQ_SYNC_CHAIN] ; // Intermediate shift regs for clock domain boundary crossing.
(*preserve*) logic [DDR3_WIDTH_DQS-1:0] PIN_OE_WDQ       [0:WDQ_SYNC_CHAIN] /* synthesis syn_keep=1 */ ; // Intermediate shift regs for clock domain boundary crossing.
                                                                              // The (*preserve*) is needed, otherwise, since the logic for each output enable DQSis a duplicate
                                                                              // and the compiler simplifies the logic down to a single logic cell and the timing of that 1 cell
                                                                              // feeding the OE for each 8 bit bank doesn't make it across all the FPGA's IOs in time to
                                                                              // to achieve a peak possible FMAX.

(*preserve*) logic      [DQ_WIDTH-1:0]  PIN_OE_WDQ_wide                     ; // Help spread and buffer the OEs individually to allow 400MHz support.
(*preserve*) logic      [DQ_WIDTH-1:0]  dq_clk		                        ; // Used to determine which clock we ought to be pumping into the IOBUF

(*preserve*) logic      [DQ_WIDTH-1:0]            RDQ_h,RDQ_l;
(*preserve*) logic      [DQ_WIDTH-1:0]            RDQ_CACHE_h   [0:(3+RDQ_SYNC_CHAIN)] ;
(*preserve*) logic      [DQ_WIDTH-1:0]            RDQ_CACHE_l   [0:(3+RDQ_SYNC_CHAIN)] ;
(*preserve*) logic                                RDQS_CACHE_h  [0:(3+RDQ_SYNC_CHAIN)] ;
(*preserve*) logic                                RDQS_CACHE_l  [0:(3+RDQ_SYNC_CHAIN)] ;
(*preserve*) logic      [DQM_WIDTH-1:0]           RDQM_h,RDQM_l;                     // These are dummy placeholders for the DQ's altddio_bidir function.  The are ignored.
(*preserve*) logic      [DDR3_WIDTH_DQS-1:0]      RDQS_ph,RDQS_pl,RDQS_nh,RDQS_nl	   ;
(*preserve*) logic      [DDR3_WIDTH_DQS-1:0]      dqs_clk					; // Used to determine which clock we ought to be pumping into the IOBUF
logic      [1:0]                     RDQ_POS                = 0 ;

localparam int  RD_WIDTH  = RDQ_ENABLE_EARLY + 4 + RDQ_DISABLE_LATE ;   // Read window size.
logic [5:0]     RD_POS,RDT_POS  ;
logic           DQS_preamble,DQS_run,RDQ_rtoggle_detect,RDQ_rtoggle_prev,RDQ_rtoggle_prev2;
logic           RDQ_rtoggle ;
logic           READ_dl=0, READ_dl2=0 ;
logic [21:0]    RDATA_window       = 0 ;

always_comb     RD_POS             = 6'(CL + RDQ_DISABLE_LATE  ) ;

logic                           pCS_n;    // DDR3 CS#
logic                           pRAS_n;   // DDR3 RAS#
logic                           pCAS_n;   // DDR3 CAS#
logic                           pWE_n;    // DDR3 WE#
logic                           pODT;     // DDR3 ODT
logic   [DDR3_WIDTH_ADDR-1:0]   pA;       // DDR3 multiplexed address input bus
logic   [DDR3_WIDTH_BANK-1:0]   pBA;      // DDR3 Bank select

// Selectively insert a delay between the command port's function and IO buffer pins depending on parameter 'CMD_ADD_DLY'.
generate if (CMD_ADD_DLY) begin
                            always @(posedge DDR_CLK)  { pBA,  pA,  pRAS_n,  pCAS_n,  pWE_n,  pCS_n,  pODT} <= { BA,  A,  RAS_n,  CAS_n,  WE_n,  CS_n,  ODT};
                        end else begin
                            assign                     { pBA,  pA,  pRAS_n,  pCAS_n,  pWE_n,  pCS_n,  pODT}  = { BA,  A,  RAS_n,  CAS_n,  WE_n,  CS_n,  ODT};
                        end
endgenerate

// *****************************************************************************************************************
// DDR IO Buffers
// *****************************************************************************************************************

genvar x;
generate if (FPGA_FAMILY == "GW2A-18") begin // Gowin Arora parts.
// ****************************************
// DDR3 Memory IO port -> DDR3_CLK pins
//
// We need a reference to the global reset, hold it high
// ****************************************
    GSR GSR  
        (
        .GSRI(1'b1) 
        );

///////////////////////////////////////////////////////////////////////////
// Create the Clocks, both +ve and -ve. Always outputs
///////////////////////////////////////////////////////////////////////////
    for (x=0; x<DDR3_NUM_CK; x = x + 1) 
        begin : DDR_Clocks
            wire gowin_clock;
            wire gowin_ck_OE;

            ODDR gowin_ck_ddr_inst_p
                (
                .Q0(DDR3_CK_p[x]),      // Send +ve clock to this pin
                .Q1(gowin_ck_OE),       // Not used but save a warning
                .D0(1'b0),				// clock goes low to start
                .D1(1'b1),				// clock goes high in 2nd phase
                .TX(1'b0),				// TX=0 -> Output pin
                .CLK(DDR_CLK)			// DDR clock
                );

             ODDR gowin_ck_ddr_inst_n
                (
                .Q0(DDR3_CK_n[x]),      // Send -ve clock to this pin
                .Q1(gowin_ck_OE),       // Not used but save a warning
                .D0(1'b1),				// clock goes high to start
                .D1(1'b0),				// clock goes low in 2nd phase
                .TX(1'b0),				// TX=0 -> Output pin
                .CLK(DDR_CLK)			// DDR clock
                );
        end


///////////////////////////////////////////////////////////////////////////
// Create the Command bus : Address, always output
///////////////////////////////////////////////////////////////////////////
    for (x=0; x<DDR3_WIDTH_ADDR; x = x + 1)
        begin : Gowin_Address
            wire gowin_addr_OE;         // unused

			ODDR gowin_addr_inst 
				(
				.Q0(DDR3_A[x]),		    // Send to this pin
                .Q1(gowin_addr_OE),     // Not used but save a warning
				.D0(pA[x]),	            // Address input
				.D1(pA[x]),		        // Duplicate during 2nd phase
				.TX(1'b0),				// TX=0 -> Output pin
				.CLK(DDR_CLK)			// DDR clock
				);
        end


///////////////////////////////////////////////////////////////////////////
// Create the Command bus : Bank select, always output
///////////////////////////////////////////////////////////////////////////
    for (x=0; x<DDR3_WIDTH_BANK; x = x + 1)
        begin : Gowin_Bank
            wire gowin_bank_OE;         // unused

			ODDR gowin_ba_inst 
				(
				.Q0(DDR3_BA[x]),        // Send to this pin
                .Q1(gowin_bank_OE),     // Not used but save a warning
				.D0(pBA[x]),	        // Bank input
				.D1(pBA[x]),		    // Duplicate during 2nd phase
				.TX(1'b0),				// TX=0 -> Output pin
				.CLK(DDR_CLK)			// DDR clock
				);
        end


///////////////////////////////////////////////////////////////////////////
// Create the Command bus : RAS, always output
///////////////////////////////////////////////////////////////////////////
    wire gowin_ras_OE;                  // unused

    ODDR gowin_ras_inst 
        (
        .Q0(DDR3_RAS_n),                // Send to this pin
        .Q1(gowin_ras_OE),              // Not used but save a warning
        .D0(pRAS_n),	                // RAS_n input
        .D1(pRAS_n),		            // Duplicate during 2nd phase
        .TX(1'b0),				        // TX=0 -> Output pin
        .CLK(DDR_CLK)			        // DDR clock
        );

///////////////////////////////////////////////////////////////////////////
// Create the Command bus : CAS, always output
///////////////////////////////////////////////////////////////////////////
    wire gowin_cas_OE;                  // unused

    ODDR gowin_cas_inst 
        (
        .Q0(DDR3_CAS_n),                // Send to this pin
        .Q1(gowin_cas_OE),              // Not used but save a warning
        .D0(pCAS_n),	                // CAS input
        .D1(pCAS_n),		            // Duplicate during 2nd phase
        .TX(1'b0),				        // TX=0 -> Output pin
        .CLK(DDR_CLK)				    // DDR clock
        );

///////////////////////////////////////////////////////////////////////////
// Create the Command bus : WE, always output
///////////////////////////////////////////////////////////////////////////
    wire gowin_we_OE;                  // unused

    ODDR gowin_we_inst 
        (
        .Q0(DDR3_WE_n),                 // Send to this pin
        .Q1(gowin_we_OE),               // Not used but save a warning
        .D0(pWE_n),	                    // CAS input
        .D1(pWE_n),		                // Duplicate during 2nd phase
        .TX(1'b0),				        // TX=0 -> Output pin
        .CLK(DDR_CLK)				    // DDR clock
        );

///////////////////////////////////////////////////////////////////////////
// Create the Command bus : CS, always output
///////////////////////////////////////////////////////////////////////////
    wire gowin_cs_OE;                  // unused

    ODDR gowin_cs_inst 
        (
        .Q0(DDR3_CS_n),                 // Send to this pin
        .Q1(gowin_cs_OE),               // Not used but save a warning
        .D0(pCS_n),	                    // CS input
        .D1(pCS_n),		                // Duplicate during 2nd phase
        .TX(1'b0),				        // TX=0 -> Output pin
        .CLK(DDR_CLK)				    // DDR clock
        );

///////////////////////////////////////////////////////////////////////////
// Create the Command bus : ODT, always output
///////////////////////////////////////////////////////////////////////////
    wire gowin_odt_OE;
    ODDR gowin_odt_inst 
        (
        .Q0(DDR3_ODT),                  // Send to this pin
        .Q1(gowin_odt_OE),              // Not used but save a warning
        .D0(pODT),	                    // CS input
        .D1(pODT),		                // Duplicate during 2nd phase
        .TX(1'b0),				        // TX=0 -> Output pin
        .CLK(DDR_CLK)		            // DDR clock
        );
  

///////////////////////////////////////////////////////////////////////////
// Create the DQS pins : Data strobe. Construct these as below:
//
// Can't use IOBUFs because they don't like different clocks on read/write
// sides. Instead, wire directly to the pads, and toggle output-enable 
// using the in-the-phase-of-the-output 'gowin_dqs_oe' signal
//
//        +-------------+      +-----------+      +-------------+         
//        |    Module   |      |   IDDR    |      | TLVDS_IOBUF |         
//        |             |      |           |      |             |         
//        |             |      |           |      |             |         
//   ---->|    rdClk    |----->| CLK       |      |             |         
//        |             |      |           |      |             |         
//        |             |      |   D [DDR] |<-----+ O [DDR]     |         
//        |             |      |           |      |             |         
//   <----+ rdData[1:0] | <----+ Q[1:0]    |      |             |         
//        |             |      | (SDR)     |      |             |         
//        |             |      +-----------+      |             |  IO+    
//        |             |                         |             +---->    
//        |             |      +-----------+      |             |         
//        |             |      |   ODDR    |      |             |         
//        |             |      |           |      |             +---->    
//   ---->|    wrClk    |----->| CLK       |      |             |  IO-    
//        |             |      |           |      |             |         
//   ---->|   txEnable  |----->| TX        |      |             |         
//        |             |      |           |      |             |         
//        |             |      |  Q1 [DDR] +----->| OEN (DDR)   |         
//        |             |      |           |      |             |         
//        |             |      |  Q0 [DDR] +----->| I [DDR]     |         
//        |             |      |           |      |             |         
//        |       2'b10 |----->| D[1:0]    |      |             |         
//        |             |      | (SDR)     |      |             |         
//        +-------------+      +-----------+      +-------------+         
//
///////////////////////////////////////////////////////////////////////////

    for (x=0; x<DDR3_WIDTH_DQS; x = x + 1)
        begin : Gowin_DQ_Strobes

            wire gowin_dqs_out;                 // Internal: ODDR->IOBUF
            wire gowin_dqs_in;                  // Internal: IOBUF->IDDR
            wire gowin_dqs_tx;                  // Internal: OE on input to ODDR
			
			// Ok, this is not normal... Gowin *really* doesn't want to 
			// have different clocks going into its IOBUF primitives for
			// read and write, so this assign will dynamically switch
			// the clock based on the OE we currently have. Yeah.
			assign dqs_clk[x] = (OE_DQS[x]) ? DDR_CLK : DDR_CLK_RDQ;

            ODDR gowin_dqs_oddr_inst  
                (
                .Q0(gowin_dqs_out),             // ODDR -> LVDS
                .Q1(gowin_dqs_tx),              // 1'b0 => output
                .D0(1'b0),                      // Input data [SDR]
                .D1(1'b1),                      // Input data [SDR]
                .TX(~OE_DQS[x]),                // Input 'output enable' 0=output
                .CLK(dqs_clk[x])                   // DDR clock
                );
 
            IDDR gowin_dqs_iddr_inst  
                (
                .Q0(RDQS_pl[x]),                // SDR to app #0
                .Q1(RDQS_ph[x]),                // SDR to app #1
                .D(gowin_dqs_in),               // DDR input signal
                .CLK(dqs_clk[x]) 				// read clock
                );

            ELVDS_IOBUF gowin_dqs_lvds_iobuf_inst
                (
                .O(gowin_dqs_in),               // LVDS -> IDDR
                .IO(DDR3_DQS_p[x]),             // +ve LVDS pad
                .IOB(DDR3_DQS_n[x]),            // -ve LVDS pad
                .I(gowin_dqs_out),              // ODDR -> LVDS
                .OEN(gowin_dqs_tx)              // input when 1'b1
                );
            
            assign RDQS_nl[x] = ~RDQS_pl[x];
            assign RDQS_nh[x] = ~RDQS_ph[x];
        end


///////////////////////////////////////////////////////////////////////////
// Create the Data bus : DQ   
//
// Can't use IOBUFs because they don't like different clocks on read/write
// sides. Instead, wire directly to the pads, and toggle output-enable 
// using the in-the-phase-of-the-output 'gowin_dq_oe' signal
//
//        +-------------+      +-----------+      +-------------+         
//        |    Module   |      |   IDDR    |      |    IOBUF    |         
//        |             |      |           |      |             |         
//        |             |      |           |      |             |         
//   ---->|    rdClk    |----->| CLK       |      |             |         
//        |             |      |           |      |             |         
//        |             |      |   D [DDR] |<-----+ O [DDR]     |         
//        |             |      |           |      |             |         
//   <----+ rdData[1:0] | <----+ Q[1:0]    |      |             |         
//        |             |      | (SDR)     |      |             |         
//        |             |      +-----------+      |             | 
//        |             |                         |             | IO    
//        |             |      +-----------+      |             +---->          
//        |             |      |   ODDR    |      |             |         
//        |             |      |           |      |             |    
//   ---->|    wrClk    |----->| CLK       |      |             |    
//        |             |      |           |      |             |         
//   ---->|   txEnable  |----->| TX        |      |             |         
//        |             |      |           |      |             |         
//        |             |      |  Q1 [DDR] +----->| OEN (DDR)   |         
//        |             |      |           |      |             |         
//        |             |      |  Q0 [DDR] +----->| I [DDR]     |         
//        |             |      |           |      |             |         
//   ---->| wrData[1:0] |----->| D[1:0]    |      |             |         
//        |             |      | (SDR)     |      |             |         
//        +-------------+      +-----------+      +-------------+         
//
///////////////////////////////////////////////////////////////////////////
    for (x=0; x<DQ_WIDTH; x = x + 1)
        begin : gowin_DQ_bus

            wire gowin_dq_out;
            wire gowin_dq_in;
            wire gowin_dq_tx_out;

			// See above comment in DQS code for this...
			assign dq_clk[x] = (PIN_OE_WDQ_wide[x]) ? DDR_CLK_WDQ : DDR_CLK_RDQ;

            ODDR gowin_dq_oddr_inst  
                (
                .Q0(gowin_dq_out),                  // ODDR -> IOBUF
                .Q1(gowin_dq_tx_out),               // OE   -> IOBUF, 1'b0 => output
                .D0(PIN_WDATA_PIPE_h[0][x]),        // Input data [SDR]
                .D1(PIN_WDATA_PIPE_l[0][x]),        // Input data [SDR]
                .TX(~PIN_OE_WDQ_wide[x]),           // Input 'output enable' 1'b0=out
                .CLK(dq_clk[x])                     // write clock
                );

            // sync to negedge instead of posedge, 1/2 clock earlier output
            //defparam gowin_dq_oddr_inst.TXCLK_POL   = 1'b1; 

            IDDR gowin_dq_iddr_inst  
                (
                .Q0(RDQ_l[x]),                      // SDR to app #0
                .Q1(RDQ_h[x]),                      // SDR to app #1
                .D(gowin_dq_in),                    // DDR input signal
                .CLK(dq_clk[x])                     // read clock
                );

            IOBUF gowin_dq_iobuf_inst
                (
                .O(gowin_dq_in),                    // IOBUF -> IDDR
                .IO(DDR3_DQ[x]),                    // DQ pad
                .I(gowin_dq_out),                   // ODDR -> IOBUF
                .OEN(gowin_dq_tx_out)               // input when 1'b1
                );
        end
    

///////////////////////////////////////////////////////////////////////////
// Create the Command bus : data-lane masks
///////////////////////////////////////////////////////////////////////////
    for (x=0; x<DDR3_WIDTH_DM; x = x + 1)
        begin : gowin_DQM
            wire gowin_dqm_OE;                      // unused

			ODDR gowin_dqm_inst 
				(
				.Q0(DDR3_DM[x]),                    // Send to this pin
                .Q1(gowin_dqm_OE),                  // Not used but save a warning
				.D0(PIN_WMASK_PIPE_h[0][x]),        // 'high' bit of mask
				.D1(PIN_WMASK_PIPE_l[0][x]),        // 'low' bit of mask 
				.TX(1'b0),				            // TX=0 -> Output pin
				.CLK(DDR_CLK_WDQ)                   // DDR write-clock
				);
        end

end endgenerate

// *****************************************************************************************************************
// *****************************************************************************************************************
// *****************************************************************************************************************
// DDR3 Memory IO port -> SDR command port
// *****************************************************************************************************************
// *****************************************************************************************************************
// *****************************************************************************************************************
logic WRITE_dlq=0;

always_ff @(posedge DDR_CLK) begin

WRITE_dlq  <= WRITE;
READ_dl    <= READ ;

        // Generate the OE signal for the DQS if a write command is received. 
        if (WRITE!=WRITE_dlq)     OE_DQS_PIPE <= {OE_DQS_PIPE [20:0],1'b0} | ({DQS_WIDTH{1'b1}});  // Fill and shift the OE_DQS time slot..
        else                      OE_DQS_PIPE <= {OE_DQS_PIPE [20:0],1'b0};                        // Left shift OE_DQS sequence.

        for (int i=0 ; i<DDR3_WIDTH_DQS ; i++) OE_DQSp2[i] <= OE_DQS_PIPE[DQS_POS-3];       // subtract 3 for the additional output latch.
                                               OE_DQSp     <= OE_DQSp2              ;
                                               OE_DQS      <= OE_DQSp               ;

end // always

// *****************************************************************************************************************
// *****************************************************************************************************************
// *****************************************************************************************************************
// DDR3 Memory Read Data port de-serializer.
// *****************************************************************************************************************
// *****************************************************************************************************************
// *****************************************************************************************************************
logic        RD_WINDOW;
always_comb  RD_WINDOW = RDATA_window[RD_POS+RDQ_SYNC_CHAIN+3+CMD_ADD_DLY+(GOWIN_ENABLE*GOWIN_READ_OFFSET)]; // The extra '+3' counts for the extra latching of input to the 'RDQ_CACHE_x[0]'

(*preserve*) logic RDATA_toggle_int   =0;//,RDATA_toggle_int2  =0;
(*preserve*) logic RDATA_toggle_int_a1=0,RDATA_toggle_int_a2=0;
(*preserve*) logic                       RDATA_toggle_int_b2=0;
(*preserve*) logic RDATA_toggle_int_c1=0,RDATA_toggle_sint  =0;
(*preserve*) logic [DDR3_RWDQ_BITS-1:0]  RDATA_int          =0;
(*preserve*) logic [7:0]                 RDATA_store_b      =8'b00000000;

always_comb  RDQ_rtoggle_detect = ( RDQ_rtoggle_prev2 != RDQ_rtoggle_prev );

always_ff @(posedge DDR_CLK_RDQ) begin
                                            RDQ_CACHE_h[0]    <= RDQ_h;                       // Shift in the input read data
                                            RDQ_CACHE_l[0]    <= RDQ_l;                       // Shift in the input read data
    for (int i=0; i<(3+RDQ_SYNC_CHAIN);i++) RDQ_CACHE_h[i+1]  <= RDQ_CACHE_h[i];              // Shift the input across the cache
    for (int i=0; i<(3+RDQ_SYNC_CHAIN);i++) RDQ_CACHE_l[i+1]  <= RDQ_CACHE_l[i];              // Shift the input across the cache
                                            RDQS_CACHE_h[0]   <= RDQS_ph[0];                  // Shift in the DQS status
                                            RDQS_CACHE_l[0]   <= RDQS_pl[0];                  // Shift in the DQS status
    for (int i=0; i<(3+RDQ_SYNC_CHAIN);i++) RDQS_CACHE_h[i+1] <= RDQS_CACHE_h[i];             // Shift the status across the cache
    for (int i=0; i<(3+RDQ_SYNC_CHAIN);i++) RDQS_CACHE_l[i+1] <= RDQS_CACHE_l[i];             // Shift the status across the cache


                             READ_dl2          <= READ_dl  ;
                             RDQ_rtoggle_prev  <= READ_dl2 ;                                   // Latch and separate the toggle from the DDR_CK
                             RDQ_rtoggle_prev2 <= RDQ_rtoggle_prev;                           // clock domain to this DDR_CLK_RDQ clock domain.
    if (!RDQ_rtoggle_detect) RDATA_window <= {RDATA_window[20:0],1'b0};                       // No read toggle detected, shift the read window to the left
    else                     RDATA_window <= {RDATA_window[20:0],1'b0} | {(RD_WIDTH){1'b1}};  // Read toggle detected, add an enable to the window


    if (!(RDQS_CACHE_h[RDQ_SYNC_CHAIN]==0 && RDQS_CACHE_l[RDQ_SYNC_CHAIN]==1)) begin      // No valid read data DQS signal pattern, so keep the RDATA_store & RDQ_POS in reset state.
             RDATA_store   <= 0 ;                                                         // Reset due to preamble
             RDATA_store_b <= 8'b00000000 ;                                               // Reset due to preamble
             RDQ_POS       <= 1 ;                                                         // Reset due to preamble
    end else if ( RD_WINDOW ) begin                                                       // Only generate a single RDATA_store copy read data strobe when an unbroken
                                                                                          // 4 count DQS clock pattern is continuously running inside the read window.
                                                RDQ_POS       <= RDQ_POS + 1'b1 ;
                                if (RDQ_POS==3) RDATA_store   <= 1'b1 ;                   // Help FMAX further down the line by making
                                else            RDATA_store   <= 1'b0 ;                   // Multiple RDATA_stores to minimize fanout with dedicated register copies.
                                if (RDQ_POS==3) RDATA_store_b <= 8'b11111111 ;
                                else            RDATA_store_b <= 8'b00000000 ;
    end else begin
             RDATA_store   <= 0 ;                                                         // No more active read window, force end the read stat.                                                         // No more active read window, force end the read stat.
             RDATA_store_b <= 8'b00000000 ;                                               // No more active read window, force end the read stat.                                                         // No more active read window, force end the read stat.
             RDQ_POS       <= 1 ;                                                         // Make sure a false broken read must run for 4 good clocks at the beginning of the next read window.
             end

        // When a RDATA_store is received, copy the RDQ_CACHE fifo into the RDATAt output and toggle the RDQ_toggle status flag.
        for (int i=0;i<4;i+=1)  begin
                                if ( RDATA_store_b[i*2+0] ) RDATA_int[ ((i)*2+0)*DQ_WIDTH  +: DQ_WIDTH  ] <= RDQ_CACHE_h[i+RDQ_SYNC_CHAIN] ; // Big Endian BL8 burst
                                if ( RDATA_store_b[i*2+1] ) RDATA_int[ ((i)*2+1)*DQ_WIDTH  +: DQ_WIDTH  ] <= RDQ_CACHE_l[i+RDQ_SYNC_CHAIN] ;
                                end

                                if ( RDATA_store )      RDATA_toggle_int  <= !RDATA_toggle_int  ;
                                                      //RDATA_toggle_int2 <= RDATA_toggle_int   ; // Shift delay the RDATA_toggle data valid output so that all paths of RDATA itself is guaranteed


end // Always


// *****************************************************************************************************************
// Bring the read data from the DDR_CLK_RDQ clock domain to the DDR_CLK clock domain.
// BHG_EXTRA_SPEED
// *****************************************************************************************************************
//generate if (BHG_EXTRA_SPEED) begin

        always_ff @(posedge DDR_CLK) begin
        
        // Here we are manually splitting up the data latch enables into 2 banks across entire data buss to help FMAX.  It's really tough to achieve a reliable 400MHz FMAX on slow Cyclone devices.
        
            RDATA_toggle_sint    <= RDATA_toggle_int   ;
        
            RDATA_toggle_int_a1  <= RDATA_toggle_sint    ; // Remember, the DDR_CLK_RDQ data has a random relative shift compared to the DDR_CLK clock domain depending on tuning calibration,
            RDATA_toggle_int_a2  <= (RDATA_toggle_int_a1 != RDATA_toggle_sint) ; // Wait 1 additional clock before transferring the entire BL8 chunk.
        
            RDATA_toggle_int_b2  <= (RDATA_toggle_int_a1 != RDATA_toggle_sint) ; // Wait 1 additional clock before transferring the entire BL8 chunk.
        
            RDATA_toggle_int_c1  <= RDATA_toggle_sint    ;
            RDATA_toggle         <= RDATA_toggle_int_c1 ;
        
        // Here we are manually splitting up the data latch enables into 2 banks across entire data buss to help FMAX.
            if (RDATA_toggle_int_a2) begin
                                                        RDATA [0                +: DDR3_RWDQ_BITS/2 ] <= RDATA_int [0                +: DDR3_RWDQ_BITS/2 ] ;
                                                        end
        
            if (RDATA_toggle_int_b2) begin
                                                        RDATA [DDR3_RWDQ_BITS/2 +: DDR3_RWDQ_BITS/2 ] <= RDATA_int [DDR3_RWDQ_BITS/2 +: DDR3_RWDQ_BITS/2 ] ;
                                                        end
        
        end // @DDR_CLK

//    end else begin

//            assign RDATA        = RDATA_int         ;
//            assign RDATA_toggle = RDATA_toggle_int ;
//    end

//endgenerate

// *****************************************************************************************************************
// *****************************************************************************************************************
// *****************************************************************************************************************
// DDR3 Memory WRITE DATA & MASK port serializer.
// *****************************************************************************************************************
// *****************************************************************************************************************
// *****************************************************************************************************************

// Assign at what time the WDQ command will shift in WRITE data.
logic WRITE_DL=0;
always_ff @(posedge DDR_CLK) begin
WRITE_DL   <= WRITE ;

        // Generate the output enable signal for the write data.  Make separate preserved OE buffers for every 8 bits to help the fitter route the FPGA timing.
        if (WRITE != WRITE_DL)  WDQ_OE_PIPE        <= {WDQ_OE_PIPE[20:0],1'b0} | ({WDQ_OE_WIDTH{1'b1}}) ;  // Fill and shift WDQ_OE_PIPE sequence.
        else                    WDQ_OE_PIPE        <= {WDQ_OE_PIPE[20:0],1'b0} ;                           // Just shift WDQ_OE_PIPE sequence.

        if (WRITE != WRITE_DL)  begin // A write BL8 command requested, load new WRITE data/mask &  Set OE pipes.

            for (int i=0;i<4;i++)   begin // Load in the new data into the beginning of the write data output pipe.
                                    WDATA_PIPE_h[i]    <=  WDATA[ ((i)*2+1)*DQ_WIDTH  +: DQ_WIDTH  ] ;  // Big Endian BL8 burst
                                    WMASK_PIPE_h[i]    <=  WMASK[ ((i)*2+1)*DQM_WIDTH +: DQM_WIDTH ] ;
                                    WDATA_PIPE_l[i]    <=  WDATA[ ((i)*2+0)*DQ_WIDTH  +: DQ_WIDTH  ] ;
                                    WMASK_PIPE_l[i]    <=  WMASK[ ((i)*2+0)*DQM_WIDTH +: DQM_WIDTH ] ;
                                    end
            for (int i=3;i<15;i++)  begin // Shift the remainder of the write data output pipe.
                                    WDATA_PIPE_h[i+1]  <=  WDATA_PIPE_h[i] ;
                                    WMASK_PIPE_h[i+1]  <=  WMASK_PIPE_h[i] ;
                                    WDATA_PIPE_l[i+1]  <=  WDATA_PIPE_l[i] ;
                                    WMASK_PIPE_l[i+1]  <=  WMASK_PIPE_l[i] ;
                                    end
        end else begin // no WRITE_BL8 command, just shift all the pipes along...
 
            for (int i=0;i<15;i++)  begin // Shift the entire write data output pipe.
                                    WDATA_PIPE_h[i+1]  <=  WDATA_PIPE_h[i] ;
                                    WMASK_PIPE_h[i+1]  <=  WMASK_PIPE_h[i] ;
                                    WDATA_PIPE_l[i+1]  <=  WDATA_PIPE_l[i] ;
                                    WMASK_PIPE_l[i+1]  <=  WMASK_PIPE_l[i] ;
                                    end
                                    WDATA_PIPE_h[0]    <=  0 ;
                                    WMASK_PIPE_h[0]    <=  M ;
                                    WDATA_PIPE_l[0]    <=  0 ;
                                    WMASK_PIPE_l[0]    <=  M ;
            end

end // DDR_CLK

// ************************************************************************************************************************************
// Cross clock domain boundary in fabric between DDR_CLK and DDR_CLK_WDQ clock domains before the data reaches the pin's DDR buffer.
// ************************************************************************************************************************************

always_ff @(posedge DDR_CLK_WDQ) begin
        for (int i=0 ; i<DDR3_WIDTH_DQS ; i++)  PIN_OE_WDQ      [WDQ_SYNC_CHAIN][i] <= WDQ_OE_PIPE [WDQ_OE_POS -WDQ_SYNC_CHAIN-1] ; // subtract 1 for the additional output latch.

    if (!WDQ_CLK_270) begin
                                                PIN_WMASK_PIPE_h[WDQ_SYNC_CHAIN]    <= WMASK_PIPE_h[WDQ_OUT_POS-WDQ_SYNC_CHAIN-1] ;
                                                PIN_WMASK_PIPE_l[WDQ_SYNC_CHAIN]    <= WMASK_PIPE_l[WDQ_OUT_POS-WDQ_SYNC_CHAIN-1] ;
                                                PIN_WDATA_PIPE_h[WDQ_SYNC_CHAIN]    <= WDATA_PIPE_h[WDQ_OUT_POS-WDQ_SYNC_CHAIN-1] ;
                                                PIN_WDATA_PIPE_l[WDQ_SYNC_CHAIN]    <= WDATA_PIPE_l[WDQ_OUT_POS-WDQ_SYNC_CHAIN-1] ;
    end else begin   // Flip the high and low data, plus shift the low word ahead by one
                                                PIN_WMASK_PIPE_l[WDQ_SYNC_CHAIN]    <= WMASK_PIPE_h[WDQ_OUT_POS-WDQ_SYNC_CHAIN-2] ;
                                                PIN_WMASK_PIPE_h[WDQ_SYNC_CHAIN]    <= WMASK_PIPE_l[WDQ_OUT_POS-WDQ_SYNC_CHAIN-1] ;
                                                PIN_WDATA_PIPE_l[WDQ_SYNC_CHAIN]    <= WDATA_PIPE_h[WDQ_OUT_POS-WDQ_SYNC_CHAIN-2] ;
                                                PIN_WDATA_PIPE_h[WDQ_SYNC_CHAIN]    <= WDATA_PIPE_l[WDQ_OUT_POS-WDQ_SYNC_CHAIN-1] ; 
    end

    if (WDQ_SYNC_CHAIN>0) begin
        for (int i=1 ; i<=WDQ_SYNC_CHAIN ; i++) begin
                                                PIN_OE_WDQ      [i-1]               <= PIN_OE_WDQ      [i] ;
                                                PIN_WMASK_PIPE_h[i-1]               <= PIN_WMASK_PIPE_h[i] ;
                                                PIN_WMASK_PIPE_l[i-1]               <= PIN_WMASK_PIPE_l[i] ;
                                                PIN_WDATA_PIPE_h[i-1]               <= PIN_WDATA_PIPE_h[i] ;
                                                PIN_WDATA_PIPE_l[i-1]               <= PIN_WDATA_PIPE_l[i] ;
                                                end
    end

    // Manually spread out the single WDQ OE into individual logic cells making an OE for each write data bit to help achieve a flawless 400MHz FMAX
    // since Quartus' 'Perform Register Duplication for Performance' physical synthesis doesn't seem to be smart enough to do this automatically.
    for (int i=0 ; i<DDR3_WIDTH_DQS ; i++)      PIN_OE_WDQ_wide[i*8+:8]             <= {8{PIN_OE_WDQ[1+WDQ_OE_ENABLE_EARLY][i]}} ;

end // DDR_CLK_WDQ

endmodule
