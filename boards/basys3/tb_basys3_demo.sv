`timescale 1ns/1ps
`default_nettype none
module tb_basys3_demo;
    reg clk=0;
    always #5 clk=~clk;
    reg btnC=0,btnU=0;
    reg [3:0] sw=0;
    wire [15:0] led;
    wire [6:0] seg;
    wire dp;
    wire [3:0] an;
    basys3_demo_top #(.DEBOUNCE_CYCLES(3),.AUTO_CYCLES(60),.POWER_ON_CYCLES(8)) dut (.*);
    integer i, actions=0, seen_digits=0;
    reg [31:0] before_rx;
    reg [4:0] expected_outcome;
    task clocks(input integer n);
        repeat(n) begin @(posedge clk); #1; end
    endtask
    always @(posedge clk) begin
        if (!dut.rst && dut.event_valid) begin
            if (dut.event_index!==0 || dut.event_symbol!==64'h4141504c20202020 || dut.event_quantity!==100)
                $fatal(1,"Board demo event metadata");
            if (dut.event_sequence==1 && (dut.event_action!==1 || dut.event_price!==990000))
                $fatal(1,"Board demo BUY fields");
            if (dut.event_sequence==3 && (dut.event_action!==2 || dut.event_price!==1110000))
                $fatal(1,"Board demo SELL fields");
            if (dut.event_sequence!=1 && dut.event_sequence!=3) $fatal(1,"Unexpected board event");
        end
    end
    initial begin
        clocks(20);
        if (led[7]!==1 || dut.rx_frames!==0) $fatal(1,"Power-on initialization failed");
        // A sub-debounce button glitch must not send a packet.
        btnC=1; clocks(1); btnC=0; clocks(15);
        if (dut.rx_frames!==0) $fatal(1,"Button bounce was accepted");
        for(i=0;i<8;i=i+1) begin
            sw={1'b0,i[2:0]}; clocks(12);
            before_rx=dut.rx_frames;
            btnC=1; clocks(80); // Holding a button must not send repeatedly.
            btnC=0; clocks(16);
            if(dut.rx_frames!==before_rx+1) $fatal(1,"Wrong frame count for selection %0d",i);
            case(i)
                0: begin expected_outcome=1; actions=actions+1; end
                1: expected_outcome=4;
                2: begin expected_outcome=2; actions=actions+1; end
                3: expected_outcome=8;
                default: expected_outcome=16;
            endcase
            if (led[4:0]!==expected_outcome || led[5]!==0 || dut.action_count!==actions)
                $fatal(1,"Selection %0d: outcome=%b actions=%d",i,led[4:0],dut.action_count);
        end
        if (dut.accepted_frames!==4 || dut.rejected_frames!==4 || dut.holds!==1 || dut.symbol_misses!==1)
            $fatal(1,"Board scenario accounting");
        // Every digit in a complete display scan must show 0002.
        repeat(66000) begin
            clocks(1);
            case(an)
                4'b1110: begin seen_digits=seen_digits|1; if(seg!==7'b0100100) $fatal(1,"Digit 0"); end
                4'b1101: begin seen_digits=seen_digits|2; if(seg!==7'b1000000) $fatal(1,"Digit 1"); end
                4'b1011: begin seen_digits=seen_digits|4; if(seg!==7'b1000000) $fatal(1,"Digit 2"); end
                4'b0111: begin seen_digits=seen_digits|8; if(seg!==7'b1000000) $fatal(1,"Digit 3"); end
                default: $fatal(1,"Display anode selection");
            endcase
            if(dp!==1) $fatal(1,"Decimal point should be off");
        end
        if(seen_digits!=15) $fatal(1,"Incomplete display scan");
        sw=4'b1000; clocks(350); // Auto mode sends several BUY packets.
        sw=0; clocks(40);
        if(dut.action_count<5 || dut.events_dropped!==0) $fatal(1,"Auto replay failed");
        btnU=1; clocks(6);
        if(dut.action_count!==0 || dut.rx_frames!==0) $fatal(1,"Reset did not clear counters");
        btnU=0; clocks(20);
        if(led[7]!==1 || led[5:0]!==0) $fatal(1,"Reset recovery failed");
        $display("PASS Basys 3: 8 scenarios, event fields, debounce, held button, auto replay, reset and display scan");
        $finish;
    end
    initial begin #2000000; $fatal(1,"Board test watchdog"); end
endmodule
`default_nettype wire
