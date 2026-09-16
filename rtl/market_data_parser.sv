`timescale 1ns/1ps
`default_nettype none
// 64-bit, byte-lane-zero-first Ethernet MAC receive stream, FCS stripped.
// Fixed profile: untagged Ethernet / IPv4 IHL=5 / UDP / one 24-byte tick.
module market_data_parser #(
    parameter [15:0] UDP_PORT = 16'd1234
) (
    input wire clk, input wire rst,
    input wire [63:0] s_axis_tdata,
    input wire [7:0] s_axis_tkeep,
    input wire s_axis_tvalid, input wire s_axis_tlast,
    input wire s_axis_tuser,
    output wire s_axis_tready,
    output reg tick_valid,
    output reg [63:0] tick_symbol,
    output reg [31:0] tick_sequence, tick_price, tick_quantity,
    output reg [31:0] rx_frames, accepted_frames, rejected_frames
);
    assign s_axis_tready = 1'b1; // Receive path never depends on event consumer.
    reg [3:0] beat, beat_next;
    reg bad, bad_next;
    // Fixed profile bounds: 10 IPv4 words; 20 UDP/address words plus 49.
    // Counters never wrap, so even rejected frames cannot exceed these sums.
    reg [19:0] ip_sum, ip_sum_next;
    reg [20:0] udp_sum, udp_sum_next;
    reg [15:0] udp_checksum, udp_checksum_next;
    reg [63:0] symbol, symbol_next;
    reg [31:0] seq_num, seq_next, price, price_next, quantity, quantity_next;
    reg candidate_valid, candidate_shape_ok;
    reg [31:0] candidate_ip_sum, candidate_udp_sum;
    reg [15:0] candidate_checksum;
    reg [63:0] candidate_symbol;
    reg [31:0] candidate_sequence, candidate_price, candidate_quantity;

    function automatic [15:0] word_be(input [63:0] d, input integer lane);
        word_be = {d[8*lane +: 8], d[8*(lane+1) +: 8]};
    endfunction
    function automatic checksum_valid(input [31:0] s);
        // Folding to ffff means hi+lo is ffff or 1fffe. The first is
        // exactly hi == ~lo; the second requires both halves to be ffff.
        // This avoids cascaded carry chains on the validation critical path.
        checksum_valid = (&(s[15:0] ^ s[31:16])) || (&s);
    endfunction
    wire [15:0] w0 = word_be(s_axis_tdata,0);
    wire [15:0] w1 = word_be(s_axis_tdata,2);
    wire [15:0] w2 = word_be(s_axis_tdata,4);
    wire [15:0] w3 = word_be(s_axis_tdata,6);
    // Balanced word addition; no byte-by-byte checksum feedback chain.
    wire [17:0] sum_four = (({2'b0,w0}+{2'b0,w1}) +
                            ({2'b0,w2}+{2'b0,w3}));
    always @* begin
        beat_next = (beat == 4'd15) ? beat : beat + 1'b1;
        bad_next = bad | s_axis_tuser;
        if (!s_axis_tlast && s_axis_tkeep != 8'hff) bad_next = 1'b1;
        ip_sum_next = ip_sum;
        udp_sum_next = udp_sum;
        udp_checksum_next = udp_checksum;
        symbol_next = symbol;
        seq_next = seq_num;
        price_next = price;
        quantity_next = quantity;
        case (beat)
            0: begin end // MAC DA/SA filtering belongs to MAC configuration.
            1: begin
                if (w2 != 16'h0800 || s_axis_tdata[55:48] != 8'h45)
                    bad_next = 1'b1;
                ip_sum_next = {4'b0,w3};
            end
            2: begin
                // Only DF may be set. Reserved flag, MF, and offset are rejected.
                if (w0 != 16'd52 || (w2 & 16'hbfff) != 0 ||
                    s_axis_tdata[55:48] == 0 || s_axis_tdata[63:56] != 8'd17)
                    bad_next = 1'b1;
                ip_sum_next = ip_sum + {2'b0,sum_four};
            end
            3: begin
                ip_sum_next = ip_sum + {2'b0,sum_four};
                udp_sum_next = udp_sum + ({5'b0,w1}+{5'b0,w2}) + {5'b0,w3};
            end
            4: begin
                ip_sum_next = ip_sum + {4'b0,w0};
                udp_sum_next = udp_sum + {3'b0,sum_four};
                if (w2 != UDP_PORT || w3 != 16'd32) bad_next = 1'b1;
            end
            5: begin
                udp_checksum_next = w0;
                udp_sum_next = udp_sum + {3'b0,sum_four};
                if (w1 != 16'h544b || w2 != 16'h0101) bad_next = 1'b1;
                seq_next[31:16] = w3;
            end
            6: begin
                udp_sum_next = udp_sum + {3'b0,sum_four};
                seq_next[15:0] = w0;
                symbol_next[63:16] = {w1,w2,w3};
            end
            7: begin
                udp_sum_next = udp_sum + {3'b0,sum_four};
                symbol_next[15:0] = w0;
                price_next = {w1,w2};
                quantity_next[31:16] = w3;
            end
            8: begin
                udp_sum_next = udp_sum + {5'b0,w0};
                quantity_next[15:0] = w0;
                if (!s_axis_tlast || s_axis_tkeep != 8'h03) bad_next = 1'b1;
            end
            default: bad_next = 1'b1; // Saturation prevents wrap/reinterpretation.
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            beat <= 0; bad <= 0; ip_sum <= 0;
            udp_sum <= 21'd49; // Pseudoheader protocol 17 + UDP length 32.
            udp_checksum <= 0; symbol <= 0; seq_num <= 0; price <= 0; quantity <= 0;
            candidate_valid <= 0; candidate_shape_ok <= 0;
            candidate_ip_sum <= 0; candidate_udp_sum <= 0; candidate_checksum <= 0;
            candidate_symbol <= 0; candidate_sequence <= 0;
            candidate_price <= 0; candidate_quantity <= 0;
            tick_valid <= 0; tick_symbol <= 0; tick_sequence <= 0;
            tick_price <= 0; tick_quantity <= 0;
            rx_frames <= 0; accepted_frames <= 0; rejected_frames <= 0;
        end else begin
            candidate_valid <= 0;
            tick_valid <= 0;
            // Commit only after the MAC's final-beat error indication is known.
            if (candidate_valid) begin
                if (candidate_shape_ok && checksum_valid(candidate_ip_sum) &&
                    (candidate_checksum == 0 || checksum_valid(candidate_udp_sum))) begin
                    tick_valid <= 1;
                    tick_symbol <= candidate_symbol;
                    tick_sequence <= candidate_sequence;
                    tick_price <= candidate_price;
                    tick_quantity <= candidate_quantity;
                    accepted_frames <= accepted_frames + 1'b1;
                end else rejected_frames <= rejected_frames + 1'b1;
            end
            if (s_axis_tvalid) begin
                if (s_axis_tlast) begin
                    rx_frames <= rx_frames + 1'b1;
                    candidate_valid <= 1;
                    candidate_shape_ok <= !bad_next && beat == 8 &&
                                          s_axis_tkeep == 8'h03 && quantity_next != 0;
                    candidate_ip_sum <= {12'b0,ip_sum_next};
                    candidate_udp_sum <= {11'b0,udp_sum_next};
                    candidate_checksum <= udp_checksum_next;
                    candidate_symbol <= symbol_next;
                    candidate_sequence <= seq_next;
                    candidate_price <= price_next;
                    candidate_quantity <= quantity_next;
                    beat <= 0; bad <= 0; ip_sum <= 0; udp_sum <= 21'd49;
                    udp_checksum <= 0; symbol <= 0; seq_num <= 0; price <= 0; quantity <= 0;
                end else begin
                    beat <= beat_next; bad <= bad_next;
                    ip_sum <= ip_sum_next; udp_sum <= udp_sum_next;
                    udp_checksum <= udp_checksum_next;
                    symbol <= symbol_next; seq_num <= seq_next;
                    price <= price_next; quantity <= quantity_next;
                end
            end
        end
    end
endmodule
`default_nettype wire
