`timescale 1ns/1ps
`default_nettype none
module tb_checksum;
    market_data_parser dut (.clk(1'b0),.rst(1'b1),.s_axis_tdata(64'd0),.s_axis_tkeep(8'd0),
        .s_axis_tvalid(1'b0),.s_axis_tlast(1'b0),.s_axis_tuser(1'b0));
    function automatic reference_valid(input [31:0] value);
        reg [31:0] total;
        begin
            total={16'b0,value[15:0]}+{16'b0,value[31:16]};
            total=(total & 32'hffff)+(total >> 16);
            total=(total & 32'hffff)+(total >> 16);
            reference_valid=(total==32'hffff);
        end
    endfunction
    task check(input [31:0] value);
        if (dut.checksum_valid(value) !== reference_valid(value))
            $fatal(1,"Checksum identity mismatch %h",value);
    endtask
    integer i, seed=1234, dummy;
    reg [15:0] hi, lo;
    initial begin
        dummy=$urandom(seed);
        check(32'h00000000); check(32'hffffffff);
        check(32'h0000ffff); check(32'hffff0000);
        for(i=0;i<65536;i=i+1) begin
            hi=i[15:0]; lo=~hi;
            check({hi,lo}); check({hi,lo+16'd1}); check({hi,lo-16'd1});
            check($urandom);
        end
        $display("PASS checksum identity 262148 cases against arithmetic folding");
        $finish;
    end
endmodule
`default_nettype wire
