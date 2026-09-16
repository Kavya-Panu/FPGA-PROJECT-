`timescale 1ns/1ps
`default_nettype none
module tb_event_fifo;
    parameter integer DEPTH = 3;
    localparam integer LW = $clog2(DEPTH+1);
    reg clk=0;
    always #3.2 clk=~clk;
    reg rst=1, s_valid=0, m_ready=0;
    reg [31:0] s_data=0;
    wire m_valid;
    wire [31:0] m_data, enqueued, dropped;
    wire [LW-1:0] level;
    event_fifo #(.WIDTH(32),.DEPTH(DEPTH)) dut (.*);
    reg [31:0] model [0:20000];
    integer head=0, tail=0, count=0, enq=0, drops=0;
    integer n, rng=12345, dummy;
    initial begin
        dummy=$urandom(rng);
        for (n=0;n<12000;n=n+1) begin
            @(negedge clk);
            rst = (n==0 || n==6000);
            // First phase forces full throughput, then randomized occupancy.
            s_valid = n<1000 ? 1'b1 : ($urandom_range(0,3) != 0);
            m_ready = n<1000 ? 1'b1 : ($urandom_range(0,3) != 0);
            s_data = $urandom;
            @(posedge clk);
            if (rst) begin head=0; tail=0; count=0; enq=0; drops=0; end
            else begin
                if (count>0 && m_ready) begin
                    if (m_data !== model[head]) $fatal(1,"FIFO ordering before pop");
                    head=head+1; count=count-1;
                end
                if (s_valid) begin
                    if (count<DEPTH) begin
                        model[tail]=s_data; tail=tail+1; count=count+1; enq=enq+1;
                    end else drops=drops+1;
                end
            end
            #1;
            if (int'(level)!=count || enqueued!=enq || dropped!=drops || m_valid!=(count>0))
                $fatal(1,"FIFO accounting mismatch cycle %0d",n);
            if (count>0 && m_data !== model[head]) $fatal(1,"FIFO data/stability mismatch");
            if (count==0 && m_data !== 0) $fatal(1,"FIFO empty data mismatch");
        end
        $display("PASS FIFO unit cycles=12000 depth=%0d",DEPTH);
        $finish;
    end
endmodule
`default_nettype wire
