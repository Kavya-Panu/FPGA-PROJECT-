`timescale 1ns/1ps
`default_nettype none
// Select the convention from the exact MAC/IP guide, never from its bus name.
// PG072 10G MAC: GOOD_FRAME_TUSER=1 (good=1 on TLAST).
// MACs that document bad=1: GOOD_FRAME_TUSER=0.
module mac_rx_adapter #(
    parameter integer GOOD_FRAME_TUSER = 0
) (
    input wire [63:0] mac_tdata, input wire [7:0] mac_tkeep,
    input wire mac_tvalid, mac_tlast, mac_tuser,
    output wire [63:0] parser_tdata, output wire [7:0] parser_tkeep,
    output wire parser_tvalid, parser_tlast, parser_tuser
);
    assign parser_tdata = mac_tdata;
    assign parser_tkeep = mac_tkeep;
    assign parser_tvalid = mac_tvalid;
    assign parser_tlast = mac_tlast;
    assign parser_tuser = GOOD_FRAME_TUSER ? (mac_tlast && !mac_tuser) : mac_tuser;
endmodule
`default_nettype wire
