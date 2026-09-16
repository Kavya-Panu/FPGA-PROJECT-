`timescale 1ns/1ps
`default_nettype none
module tb_mac_rx_adapter;
    reg [63:0] mac_tdata;
    reg [7:0] mac_tkeep;
    reg mac_tvalid, mac_tlast, mac_tuser;
    wire [63:0] good_data, bad_data;
    wire [7:0] good_keep, bad_keep;
    wire good_valid, good_last, good_user, bad_valid, bad_last, bad_user;
    mac_rx_adapter #(.GOOD_FRAME_TUSER(1)) good_mac (
        .mac_tdata(mac_tdata),.mac_tkeep(mac_tkeep),.mac_tvalid(mac_tvalid),
        .mac_tlast(mac_tlast),.mac_tuser(mac_tuser),.parser_tdata(good_data),
        .parser_tkeep(good_keep),.parser_tvalid(good_valid),.parser_tlast(good_last),.parser_tuser(good_user));
    mac_rx_adapter #(.GOOD_FRAME_TUSER(0)) bad_mac (
        .mac_tdata(mac_tdata),.mac_tkeep(mac_tkeep),.mac_tvalid(mac_tvalid),
        .mac_tlast(mac_tlast),.mac_tuser(mac_tuser),.parser_tdata(bad_data),
        .parser_tkeep(bad_keep),.parser_tvalid(bad_valid),.parser_tlast(bad_last),.parser_tuser(bad_user));
    integer i;
    initial begin
        for(i=0;i<8;i=i+1) begin
            {mac_tvalid,mac_tlast,mac_tuser}=i[2:0];
            mac_tdata=64'h123456789abcdef0; mac_tkeep=8'h03;
            #1;
            if ({good_data,good_keep,good_valid,good_last} !== {mac_tdata,mac_tkeep,mac_tvalid,mac_tlast} ||
                {bad_data,bad_keep,bad_valid,bad_last} !== {mac_tdata,mac_tkeep,mac_tvalid,mac_tlast})
                $fatal(1,"Adapter data/framing mismatch");
            if (good_user !== (mac_tlast && !mac_tuser) || bad_user !== mac_tuser)
                $fatal(1,"Adapter polarity mismatch");
        end
        $display("PASS MAC adapter 8 control combinations, both status conventions");
        $finish;
    end
endmodule
`default_nettype wire
