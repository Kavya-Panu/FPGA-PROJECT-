`timescale 1ns/1ps
`default_nettype none
module tb_tick_to_trade;
    parameter integer TABLE_SIZE = 8;
    parameter integer FIFO_DEPTH = 16;
    localparam integer IW = TABLE_SIZE <= 1 ? 1 : $clog2(TABLE_SIZE);
    localparam integer LW = $clog2(FIFO_DEPTH+1);
    localparam integer OW = 2 + 162 + IW + LW + 7*32;
    reg clk = 0;
    always #3.2 clk = ~clk;
    reg rst, s_axis_tvalid, s_axis_tlast, s_axis_tuser, m_event_ready;
    reg [63:0] s_axis_tdata, cfg_symbol;
    reg [7:0] s_axis_tkeep;
    reg cfg_we, cfg_enable;
    reg [IW-1:0] cfg_index;
    reg [31:0] cfg_buy_price, cfg_sell_price;
    wire s_axis_tready, cfg_error, m_event_valid;
    wire [1:0] m_event_action;
    wire [IW-1:0] m_event_index;
    wire [63:0] m_event_symbol;
    wire [31:0] m_event_sequence, m_event_price, m_event_quantity;
    wire [LW-1:0] fifo_level;
    wire [31:0] rx_frames, accepted_frames, rejected_frames, symbol_misses,
                holds, events_enqueued, events_dropped;
    tick_to_trade #(.TABLE_SIZE(TABLE_SIZE), .FIFO_DEPTH(FIFO_DEPTH)) dut (.*);
    wire [OW-1:0] observed = {cfg_error,m_event_valid,m_event_action,m_event_index,
        m_event_symbol,m_event_sequence,m_event_price,m_event_quantity,fifo_level,
        rx_frames,accepted_frames,rejected_frames,symbol_misses,holds,events_enqueued,events_dropped};
    reg [OW-1:0] expected;
    string vector_path, event_path, wave_path;
    integer fd, ef, fields, cycle = 0, transfers = 0;
    initial begin
        if (!$value$plusargs("vectors=%s", vector_path)) $fatal(1,"Missing vectors");
        if (!$value$plusargs("events=%s", event_path)) $fatal(1,"Missing events path");
        if ($value$plusargs("waves=%s", wave_path)) begin
            $dumpfile(wave_path); $dumpvars(0,tb_tick_to_trade);
        end
        fd = $fopen(vector_path,"r"); ef = $fopen(event_path,"w");
        if (!fd || !ef) $fatal(1,"Cannot open test files");
        $fwrite(ef,"cycle,action,index,symbol_hex,sequence,price,quantity\n");
        rst=1; s_axis_tvalid=0; s_axis_tlast=0; s_axis_tuser=0;
        s_axis_tdata=0; s_axis_tkeep=0; m_event_ready=0;
        cfg_we=0; cfg_enable=0; cfg_index=0; cfg_symbol=0; cfg_buy_price=0; cfg_sell_price=0;
        while (!$feof(fd)) begin
            @(negedge clk);
            fields = $fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",
                rst,s_axis_tvalid,s_axis_tlast,s_axis_tuser,s_axis_tkeep,s_axis_tdata,
                m_event_ready,cfg_we,cfg_index,cfg_enable,cfg_symbol,cfg_buy_price,
                cfg_sell_price,expected);
            if (fields != 14) $fatal(1,"Malformed vector at cycle %0d",cycle);
            @(posedge clk);
            if (!rst && m_event_valid && m_event_ready) begin
                transfers = transfers+1;
                $fwrite(ef,"%0d,%0d,%0d,%016h,%0d,%0d,%0d\n",cycle,m_event_action,
                    m_event_index,m_event_symbol,m_event_sequence,m_event_price,m_event_quantity);
            end
            #1;
            if (s_axis_tready !== 1'b1) $fatal(1,"RX unexpectedly stalled");
            if (observed !== expected) begin
                $display("Cycle %0d observed=%h expected=%h",cycle,observed,expected);
                $display("valid=%b action=%d seq=%d level=%d rx=%d accepted=%d rejected=%d misses=%d holds=%d enqueued=%d dropped=%d cfg_error=%b",
                    m_event_valid,m_event_action,m_event_sequence,fifo_level,rx_frames,
                    accepted_frames,rejected_frames,symbol_misses,holds,events_enqueued,events_dropped,cfg_error);
                $fatal(1,"Scoreboard mismatch");
            end
            cycle = cycle+1;
        end
        $fclose(fd); $fclose(ef);
        $display("PASS cycles=%0d transfers=%0d table=%0d fifo=%0d",cycle,transfers,TABLE_SIZE,FIFO_DEPTH);
        $finish;
    end
    initial begin #100000000; $fatal(1,"Simulation watchdog expired"); end
endmodule
`default_nettype wire
