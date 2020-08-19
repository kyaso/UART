`timescale 1ns/1ns

module uart_rx
#(
    parameter CLK_FREQ = 100000000,
    parameter BAUD_RATE = 2000000
)
(
    input clk,
    input rst_n,
    input rx,                   // UART RX
    output reg [7:0] rx_data_o, // Received byte out
    output reg rx_data_valid   // Whether the value at rx_data_o is valid
);
    // Start & Stop bit defines for better readability
    localparam START = 1'b0;
    localparam STOP = 1'b1;

    // FSM states
    localparam FSM_IDLE = 8'd0;
    localparam FSM_START_BIT = 8'd1;
    localparam FSM_DATA_BITS = 8'd2;
    localparam FSM_STOP_BIT = 8'd4;
    localparam FSM_DONE = 8'd8;
    localparam FSM_ERR = 8'd16;

    // How many clk ticks there are in one baud period
    localparam CLK_SAMPLE_TICKS = (CLK_FREQ / BAUD_RATE);

    // FSM state regs
    (* mark_debug = "true" *) reg [7:0] rx_fsm_state;
    reg [7:0] rx_fsm_state_next;

    // Data bit shift reg
    reg [7:0] data_bits;

    // Data bit counter
    (* mark_debug = "true" *) reg [3:0] rx_bit_cnt;

    // Sample counter
    (* mark_debug = "true" *) reg [15:0] sample_cnt;

    // FSM state transition
    always @(posedge clk)
    begin
        if(!rst_n)
            rx_fsm_state <= FSM_IDLE;
        else begin
            rx_fsm_state <= rx_fsm_state_next;
        end
    end

    // Sample counter
    always @(posedge clk)
    begin
        // Reset counter on reset OR FSM is IDLE OR sample_cnt reached specified max value 
        /* verilator lint_off WIDTH */
        if(!rst_n || (rx_fsm_state==FSM_IDLE /*&& rx==START*/) || sample_cnt==CLK_SAMPLE_TICKS-1)
        /* verilator lint_on WIDTH */
            sample_cnt <= 16'd0;
        else
            sample_cnt <= sample_cnt + 1;
    end

    // Next state logic
    always @*
    begin
        case (rx_fsm_state)
            FSM_IDLE: begin
                // Start bit has been received
                if(rx == START) begin
                   rx_fsm_state_next = FSM_START_BIT; 
                end else begin
                   rx_fsm_state_next = FSM_IDLE; 
                end
            end
            FSM_START_BIT: begin
                // Wait until mid of START bit for synchronization
                /* verilator lint_off WIDTH */
                if(sample_cnt==CLK_SAMPLE_TICKS/2) begin
                /* verilator lint_on WIDTH */
                    rx_fsm_state_next = FSM_DATA_BITS;
                end else if(rx==START) begin
                    // Stay in START_BIT state if RX line still LOW
                    rx_fsm_state_next = FSM_START_BIT;
                end else begin
                    // Go back to IDLE if START bit was too short
                    rx_fsm_state_next = FSM_IDLE; 
                end
            end
            FSM_DATA_BITS: begin
                // Receive/Sample 8 data bits
                if(rx_bit_cnt==4'd8) begin
                    rx_fsm_state_next = FSM_STOP_BIT;
                end else begin
                    rx_fsm_state_next = FSM_DATA_BITS; 
                end
            end
            FSM_STOP_BIT: begin
                // Wait until mid of STOP bit
                /* verilator lint_off WIDTH */
                if(sample_cnt==CLK_SAMPLE_TICKS/2) begin
                /* verilator lint_on WIDTH */
                    rx_fsm_state_next = FSM_DONE;
                end else begin
                    rx_fsm_state_next = FSM_STOP_BIT; 
                end
            end
            FSM_DONE: begin
                // Jump back to IDLE after one cycle
                rx_fsm_state_next = FSM_IDLE;
            end
            FSM_ERR: begin
                // In case of error, trap here
                rx_fsm_state_next = FSM_ERR;
            end
            default: begin
                // Default to IDLE
                rx_fsm_state_next = FSM_IDLE; 
            end
        endcase
    end

    // RX bit counter
    always @(posedge clk)
    begin
        // Reset counter when stop bit has been received
        if(!rst_n || rx_fsm_state==FSM_IDLE || rx_fsm_state==FSM_STOP_BIT)
            rx_bit_cnt <= 4'd0;
        // Increment counter during RX at mid of each data bit
        /* verilator lint_off WIDTH */
        else if(rx_fsm_state==FSM_DATA_BITS && sample_cnt==CLK_SAMPLE_TICKS/2) begin
        /* verilator lint_on WIDTH */
            rx_bit_cnt <= rx_bit_cnt + 1;
        end else begin
            rx_bit_cnt <= rx_bit_cnt; 
        end
    end

    // Sample RX data bits 
    always @(posedge clk)
    begin
        // Check if sample point (= middle of data bit) has been reached
        /* verilator lint_off WIDTH */
        if(rx_fsm_state==FSM_DATA_BITS && sample_cnt==CLK_SAMPLE_TICKS/2) begin
        /* verilator lint_on WIDTH */
            data_bits <= { data_bits[6:0], rx };
        end else begin
            data_bits <= data_bits; 
        end
    end

    // Write to output reg
    always @*
    begin
        // In DONE state, the received byte is presented for one cycle
        // at the rx_data_o output.
        // The order of the data_bits is due to the following:
        //      1) Data bits arrive LSB-first
        //      2) We shift in the sampled bits at the LSB-side of data_bits
        //         (see Sampling process above)
        rx_data_o = {data_bits[0], data_bits[1], data_bits[2], data_bits[3], data_bits[4], data_bits[5], data_bits[6], data_bits[7]};
        if(rx_fsm_state == FSM_DONE) begin
            rx_data_valid = 1;
        // Only present data when in DONE state
        end else begin
            // rx_data_o = 8'b0; // For now don't explicitly set data to 0, to save switching activity
            rx_data_valid = 0;
        end
    end

endmodule