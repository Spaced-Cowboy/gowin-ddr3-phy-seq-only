`timescale 1 ns / 1 ps // 1 ns steps, 1 ps precision.

///////////////////////////////////////////////////////////////////////////////
// Phase control values
// --------------------
// 0000 0°          0001 22.5°          0010 45°            0011 67.5°
// 0100 90°         0101 112.5°         0110 135°           0111 157.5°
// 1000 180°        1001 202.5°         1010 225°           1011 247.5°
// 1100 270°        1101 292.5°         1110 315°           1111 337.5°
//
// Duty cycle values
// -----------------
// 0010 2/16        0011 3/16           0100 4/16           0101 5/16
// 0110 6/16        0111 7/16           1000 8/16           1001 9/16
// 1010 10/16       1011 11/16          1100 12/16          1101 13/16
// 1110 14/16
//
// Delay parameters
// ----------------
// 0111 0.875ns     1011 1.375ns        1101 1.625ns        1110 1.75ns
// 1111 1.875ns
//
///////////////////////////////////////////////////////////////////////////////

module gowin_ddr_clocking 
   #(
    // ****************  family definition. Modelsim doesn't like me typing
    //                   this as a string
    parameter           FPGA_FAMILY         = "GW2A-18",
 
    // ****************  System clock generation and operation.

    // PLL source input clock frequency in KHz.
    parameter int        CLK_KHZ_IN         = 50000,          
    
    // Multiply factor to generate the DDR MTPS speed divided by 2.
    parameter int        CLK_IN_MULT        = 32,             
    
    // Divide factor.  When CLK_KHZ_IN is 25k,50k,75k,100k,125k,150k, 
    // use 2,4,6,8,10,12.
    parameter int        CLK_IN_DIV         = 4,              
   	
	// 270/90.  Select the write and write DQS output clock phase relative
	// to the DDR3_CLK
	parameter int        DDR3_WDQ_PHASE     = 270            
    )
    (
    input               clk,                // External clock
	input			    rst,				// External reset
    input               phase_step,         // step the phase control
    input               phase_updn,         // step phase up (1) or down (0)

    output              clk_ddrMain,        // Main DDR clock
    output              clk_ddrWrite,       // 270° phase-shifted clock
    output              clk_ddrRead,        // User-tuned clock
    output              clk_ddrClient,      // Client-interface clock
    output              clk_ddrMgmt,        // init/long-period timer

    output              locked              // Both PLLs are locked
	);

    ///////////////////////////////////////////////////////////////////////////
    // Allow definitions from the top-level-source to customise this PLL
    //
    // Define the localparam list as an int, then use it indexed in the PLL to
    // make it work in both synthesis and simulation
    ///////////////////////////////////////////////////////////////////////////
	localparam 	int 	write_phase[0:15] 	='{"0000","0001","0010","0011",
											   "0100","0101","0110","0111",
											   "1000","1001","1010","1011",
											   "1100","1101","1110","1111"};
	localparam 	int 	duty_phase[0:15] 	='{"1100","1101","1110","1111",
											   "0000","0001","0010","0011",
											   "0100","0101","0110","0111",
											   "1000","1001","1010","1011"};
    localparam  		phaseIndex		    = (DDR3_WDQ_PHASE * 16 / 360);
    
    ///////////////////////////////////////////////////////////////////////////
    // Provide the step-based facade over the direct-program Gowin interface
    ///////////////////////////////////////////////////////////////////////////
    reg     [3:0]       duty;               // Duty cycle, 50/50 = 8 + phase
    reg     [2:0]       phase;              // Phase to present to PLL
    reg                 lastPhaseStep;      // Look for the level-transition

    always @ (posedge clk)  
        begin
            if (rst) 
                begin
                    phase           <= 3'b0;
                    duty            <= 4'b0;
                    lastPhaseStep   <= 1'b0;
                end
            else    
                begin
                    if ((phase_step == 1'b1) && (lastPhaseStep == 1'b0))
                        if (phase_updn == 1'b0)
                            begin
                                phase   <= phase - 3'b1;

                                // current phase + (8-2)
                                duty    <= {phase,1'b0} + 4'h6;     
                            end
                        else
                            begin
                                phase   <= phase + 3'b1;

                                // current phase + (8+2)
                                duty    <= {phase,1'b0} + 4'hA;     
                            end

                    lastPhaseStep <= phase_step;
                end
        end
    

    ///////////////////////////////////////////////////////////////////////////
    // Instantiate the PLL for:
    //
    // CLKOUT       - the main DDR3 clock
    // CLKOUTP      - the user-changeable-phase read-clock
    // CLKOUTD      - the client-interface clock
    ///////////////////////////////////////////////////////////////////////////
    wire lock_pll1;
    wire clkoutd3_pll1;
    rPLL ddr3_pll1 
        (
        .CLKOUT(clk_ddrMain),
        .LOCK(lock_pll1),
        .CLKOUTP(clk_ddrRead),
        .CLKOUTD(clk_ddrClient),
        .CLKOUTD3(clkoutd3_pll1),
        .RESET(rst),
        .RESET_P(1'b0),
        .CLKIN(clk),
        .CLKFB(1'b0),
        .FBDSEL({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
        .IDSEL({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
        .ODSEL({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
        .PSDA({phase,1'b0}),
        .DUTYDA(duty),
        .FDLY(4'b0)
        );

    defparam ddr3_pll1.FCLKIN           = (CLK_KHZ_IN /1000);
    defparam ddr3_pll1.DYN_IDIV_SEL     = "false";
    defparam ddr3_pll1.IDIV_SEL         = (CLK_IN_DIV-1);
    defparam ddr3_pll1.DYN_FBDIV_SEL    = "false";
    defparam ddr3_pll1.FBDIV_SEL        = (CLK_IN_MULT-1);
    defparam ddr3_pll1.DYN_ODIV_SEL     = "false";
    defparam ddr3_pll1.ODIV_SEL         = 2;
    defparam ddr3_pll1.PSDA_SEL         = "0000";
    defparam ddr3_pll1.DYN_DA_EN        = "true";
    defparam ddr3_pll1.DUTYDA_SEL       = "1000";
    defparam ddr3_pll1.CLKOUT_FT_DIR    = 1'b1;
    defparam ddr3_pll1.CLKOUTP_FT_DIR   = 1'b1;
    defparam ddr3_pll1.CLKOUT_DLY_STEP  = 0;
    defparam ddr3_pll1.CLKOUTP_DLY_STEP = 0;
    defparam ddr3_pll1.CLKFB_SEL        = "internal";
    defparam ddr3_pll1.CLKOUT_BYPASS    = "false";
    defparam ddr3_pll1.CLKOUTP_BYPASS   = "false";
    defparam ddr3_pll1.CLKOUTD_BYPASS   = "false";
    defparam ddr3_pll1.DYN_SDIV_SEL     = 2;
    defparam ddr3_pll1.CLKOUTD_SRC      = "CLKOUT";
    defparam ddr3_pll1.CLKOUTD3_SRC     = "CLKOUT";
    defparam ddr3_pll1.DEVICE           = "GW2A-18";   // seems to no longer accept FPGA_FAMILY(!)


    ///////////////////////////////////////////////////////////////////////////
    // Instantiate the PLL for:
    //
    // CLKOUT       - unused
    // CLKOUTP      - the DDR3-write clock with phase DDR3_WDQ_PHASE
    // CLKOUTD      - the internal logic clock
    ///////////////////////////////////////////////////////////////////////////
    wire lock_pll2;
    wire dummyClock;
    wire clkoutd3_pll2;
    
    rPLL ddr3_pll2 (
        .CLKOUT(dummyClock),
        .LOCK(lock_pll2),
        .CLKOUTP(clk_ddrWrite),
        .CLKOUTD(clk_ddrMgmt),
        .CLKOUTD3(clkoutd3_pll2),
        .RESET(rst),
        .RESET_P(1'b0),
        .CLKIN(clk),
        .CLKFB(1'b0),
        .FBDSEL({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
        .IDSEL({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
        .ODSEL({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
        .PSDA({1'b0,1'b0, 1'b0, 1'b0}),
        .DUTYDA({1'b0, 1'b0, 1'b0, 1'b0}),
        .FDLY({1'b0, 1'b0, 1'b0, 1'b0})
    );

    defparam ddr3_pll2.FCLKIN           = (CLK_KHZ_IN /1000);
    defparam ddr3_pll2.DYN_IDIV_SEL     = "false";
    defparam ddr3_pll2.IDIV_SEL         = (CLK_IN_DIV-1);
    defparam ddr3_pll2.DYN_FBDIV_SEL    = "false";
    defparam ddr3_pll2.FBDIV_SEL        = (CLK_IN_MULT-1);
    defparam ddr3_pll2.DYN_ODIV_SEL     = "false";
    defparam ddr3_pll2.ODIV_SEL         = 2;
    defparam ddr3_pll2.DYN_DA_EN        = "false";
    defparam ddr3_pll2.CLKOUT_FT_DIR    = 1'b1;
    defparam ddr3_pll2.CLKOUTP_FT_DIR   = 1'b1;
    defparam ddr3_pll2.CLKOUT_DLY_STEP  = 0;
    defparam ddr3_pll2.CLKOUTP_DLY_STEP = 0;
    defparam ddr3_pll2.CLKFB_SEL        = "internal";
    defparam ddr3_pll2.CLKOUT_BYPASS    = "false";
    defparam ddr3_pll2.CLKOUTP_BYPASS   = "false";
    defparam ddr3_pll2.CLKOUTD_BYPASS   = "false";
    defparam ddr3_pll2.DYN_SDIV_SEL     = 4;
    defparam ddr3_pll2.CLKOUTD_SRC      = "CLKOUT";
    defparam ddr3_pll2.CLKOUTD3_SRC     = "CLKOUT";
    defparam ddr3_pll2.DEVICE           = "GW2A-18";    // seems to no longer accept FPGA_FAMILY(!)
	defparam ddr3_pll2.DUTYDA_SEL 	    = duty_phase[phaseIndex[3:0]];
	defparam ddr3_pll2.PSDA_SEL 	    = write_phase[phaseIndex[3:0]];

    assign locked = lock_pll1 & lock_pll2;

endmodule

