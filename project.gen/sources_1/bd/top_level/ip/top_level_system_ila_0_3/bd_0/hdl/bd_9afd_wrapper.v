//Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Command: generate_target bd_9afd_wrapper.bd
//Design : bd_9afd_wrapper
//Purpose: IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module bd_9afd_wrapper
   (clk,
    probe0,
    probe1,
    probe2,
    probe3,
    probe4,
    probe5,
    probe6,
    probe7);
  input clk;
  input [0:0]probe0;
  input [3:0]probe1;
  input [3:0]probe2;
  input [0:0]probe3;
  input [0:0]probe4;
  input [63:0]probe5;
  input [31:0]probe6;
  input [0:0]probe7;

  wire clk;
  wire [0:0]probe0;
  wire [3:0]probe1;
  wire [3:0]probe2;
  wire [0:0]probe3;
  wire [0:0]probe4;
  wire [63:0]probe5;
  wire [31:0]probe6;
  wire [0:0]probe7;

  bd_9afd bd_9afd_i
       (.clk(clk),
        .probe0(probe0),
        .probe1(probe1),
        .probe2(probe2),
        .probe3(probe3),
        .probe4(probe4),
        .probe5(probe5),
        .probe6(probe6),
        .probe7(probe7));
endmodule
