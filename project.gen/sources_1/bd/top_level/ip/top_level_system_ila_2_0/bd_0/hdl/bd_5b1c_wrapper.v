//Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Command: generate_target bd_5b1c_wrapper.bd
//Design : bd_5b1c_wrapper
//Purpose: IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module bd_5b1c_wrapper
   (clk,
    probe0,
    probe1,
    probe2,
    probe3,
    probe4,
    probe5);
  input clk;
  input [0:0]probe0;
  input [0:0]probe1;
  input [9:0]probe2;
  input [7:0]probe3;
  input [31:0]probe4;
  input [1:0]probe5;

  wire clk;
  wire [0:0]probe0;
  wire [0:0]probe1;
  wire [9:0]probe2;
  wire [7:0]probe3;
  wire [31:0]probe4;
  wire [1:0]probe5;

  bd_5b1c bd_5b1c_i
       (.clk(clk),
        .probe0(probe0),
        .probe1(probe1),
        .probe2(probe2),
        .probe3(probe3),
        .probe4(probe4),
        .probe5(probe5));
endmodule
