//=============================================================================
// Module: spi_clk_div.v
//
// This is an integer clock divider: It creates an output clock with a 
// frequency that can be derived from the input clock frequency by integer
// division.
//
// On the rising edge of clken, the state of clkout will always be high
//=============================================================================
module spi_clk_div #
(
    parameter CLKIN_HZ        = 100000000,
    parameter CLKOUT_HZ       =  50000000,
    parameter CYCLE_COUNT_WIDTH = 10
)
(
    // Source clock
    input   clkin,

    // The divided down clock signal
    output  clkout,

    // Enables or disables the clkout signal
    input   clken,

    // These are high for one clkin cycle on the clkout edges
    output  rising_edge, falling_edge,

    // Counts the number of clkout high-going edges while clken=1
    output [CYCLE_COUNT_WIDTH-1:0] cycle_count
);

//=============================================================================
// This will generate a compile time error if CLKIN_HZ is not evenly divisible
// by CLKOUT_HZ
//=============================================================================
localparam IDX=((CLKIN_HZ % CLKOUT_HZ) == 0) ? 0 : 999999999;
reg compile_error[IDX:0];
//=============================================================================

//=============================================================================
// Determine the length of a full clkout clock cycle in terms in clkin cycles.
//
// If there are an odd number of clkin cycles in a clkout cycle, make the
// "high" state of clkout one cycle longer than the "low" state
//=============================================================================
localparam EXTRA_CYCLE = (CLKIN_HZ / CLKOUT_HZ) & 1;
localparam LOW_CYCLES  = (CLKIN_HZ / CLKOUT_HZ) / 2;
localparam HIGH_CYCLES = (CLKIN_HZ / CLKOUT_HZ) / 2 + EXTRA_CYCLE;
//=============================================================================

// This is state of our state machine *and* the state of clkout
reg fsm_state;

// Find out whether HIGH_CYCLES or LOW_CYCLES is the highest value
localparam MAX_CYCLES = (HIGH_CYCLES > LOW_CYCLES) ? HIGH_CYCLES : LOW_CYCLES;

// This is a countdown timer
reg[$clog2(MAX_CYCLES)-1:0] countdown;

// We're going to count the number of rising edges on clkout
reg[CYCLE_COUNT_WIDTH-1:0] cycle_count_reg;

//=============================================================================
// This state machine drives clkout up and down with the specied periods for
// the high state and low state
//=============================================================================
always @(posedge clkin) begin

    // This always counts down to zero
    if (countdown) countdown <= countdown - 1;

    // If clock-enable is low, ensure that when it goes high,
    // a rising edge on clkout will occur
    if (clken == 0) begin
        fsm_state       <= 1;
        cycle_count_reg <= 1;
        countdown       <= HIGH_CYCLES - 1;
    end

    else case(fsm_state)

        // clkout is currently low.  Is it time to drive it high?
        0:  if (countdown == 0) begin
                countdown       <= HIGH_CYCLES - 1;
                fsm_state       <= 1;
                cycle_count_reg <= cycle_count_reg + 1;
            end

        // clkout is currently high.  Is it time to drive it low?
        1:  if (countdown == 0) begin
                countdown <= LOW_CYCLES - 1;
                fsm_state <= 0;
            end 

    endcase

end
//=============================================================================

// clkout is the state of our state machine, gated by clken
assign clkout = fsm_state & clken;

// The "cycle_count" port is gated by clken
assign cycle_count = (clken) ? cycle_count_reg : 0;

//=============================================================================
// This block detects the edges of clkout
//=============================================================================
reg prior_clkout;
always @(posedge clkin) prior_clkout = clkout;
assign rising_edge  = (prior_clkout == 0) & (clkout == 1);
assign falling_edge = (prior_clkout == 1) & (clkout == 0);
//=============================================================================

endmodule
