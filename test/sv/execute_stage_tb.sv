/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: execute_stage_tb.sv
 */

module execute_stage_tb;

    import clk_params::*;
    import instruction::*;
    import pipeline_status::*;
    import forwarding::*;
    import op::*;

    /*verilator lint_off UNUSED*/
    logic clk, clk_vga;
    logic rst;
    /*verilator lint_on UNUSED*/

    // --------------------------------------------------------------------------------------------
    // System clock
    initial begin
        clk = 1;
        forever begin
            #(int'(SIM_CYCLES_PER_SYS_CLK / 2));
            clk = ~clk;
        end
    end

    // VGA pixel clock
    initial begin
        clk_vga = 1;
        forever begin
            #(int'(SIM_CYCLES_PER_VGA_CLK / 2));
            clk_vga = ~clk_vga;
        end
    end

    // --------------------------------------------------------------------------------------------
    // test bench variables

    int error_count = 0;

    // --------------------------------------------------------------------------------------------
    // device under test

    instruction::t dut_instruction_in;
    instruction::t dut_instruction_out;

    logic [31:0] dut_program_counter_in;
    logic [31:0] dut_program_counter_out;

    logic [31:0] dut_rs1_data_in;
    logic [31:0] dut_rs2_data_in;

    logic [31:0] dut_next_pc_out;
    logic [31:0] dut_rd_data_out;
    logic [31:0] dut_source_data_out;

    logic [31:0] dut_jump_address_in;
    logic [31:0] dut_jump_address_out;

    pipeline_status::forwards_t  dut_status_forwards_in;
    pipeline_status::forwards_t  dut_status_forwards_out;

    pipeline_status::backwards_t dut_status_backwards_in;
    pipeline_status::backwards_t dut_status_backwards_out;

    forwarding::t dut_forwarding_out;

    // --------------------------------------------------------------------------------------------
    // DUT

    execute_stage dut (
        .clk(clk),
        .rst(rst),

        // Inputs
        .rs1_data_in(dut_rs1_data_in),
        .rs2_data_in(dut_rs2_data_in),

        .instruction_in(dut_instruction_in),

        .program_counter_in(dut_program_counter_in),

        // Outputs
        .source_data_reg_out(dut_source_data_out),

        .rd_data_reg_out(dut_rd_data_out),

        .instruction_reg_out(dut_instruction_out),

        .program_counter_reg_out(dut_program_counter_out),

        .next_program_counter_reg_out(dut_next_pc_out),

        .forwarding_out(dut_forwarding_out),

        // Pipeline control
        .status_forwards_in(dut_status_forwards_in),

        .status_forwards_out(dut_status_forwards_out),

        .status_backwards_in(dut_status_backwards_in),

        .status_backwards_out(dut_status_backwards_out),

        .jump_address_backwards_in(dut_jump_address_in),

        .jump_address_backwards_out(dut_jump_address_out)
    );

    // --------------------------------------------------------------------------------------------
    // MAIN TEST

    initial begin

        $dumpfile("execute_stage_tb.fst");
        $dumpvars(0, execute_stage_tb);

        reset_module_inputs();

        // ----------------------------------------------------------------------------------------
        // RESET
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) RESET", $time());

        perform_rst();

        // ----------------------------------------------------------------------------------------
        // TEST 1 : ADDI
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST ADDI", $time());

        @(posedge clk); #1;

        dut_instruction_in.op          = op::ADDI;
        dut_instruction_in.rd_address  = 5'd1;
        dut_instruction_in.rs1_address = 5'd2;
        dut_instruction_in.immediate   = 32'd5;

        dut_rs1_data_in = 32'd10;
        dut_rs2_data_in = 32'd0;

        dut_program_counter_in = 32'h00000100;

        dut_status_forwards_in  = pipeline_status::VALID;
        dut_status_backwards_in = pipeline_status::READY;

        @(posedge clk); #1;

        assert(dut_rd_data_out == 32'd15)
        else begin
            $display("ERROR: ADDI failed");
            error_count++;
        end;

        assert(dut_next_pc_out == 32'h00000104)
        else begin
            $display("ERROR: ADDI next_pc failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST 2 : SUB
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST SUB", $time());

        @(posedge clk); #1;

        dut_instruction_in.op = op::SUB;

        dut_rs1_data_in = 32'd20;
        dut_rs2_data_in = 32'd7;

        @(posedge clk); #1;

        assert(dut_rd_data_out == 32'd13)
        else begin
            $display("ERROR: SUB failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST 3 : AND
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST AND", $time());

        @(posedge clk); #1;

        dut_instruction_in.op = op::AND;

        dut_rs1_data_in = 32'd12;
        dut_rs2_data_in = 32'd10;

        @(posedge clk); #1;

        assert(dut_rd_data_out == 32'd8)
        else begin
            $display("ERROR: AND failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST 4 : OR
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST OR", $time());

        @(posedge clk); #1;

        dut_instruction_in.op = op::OR;

        dut_rs1_data_in = 32'd12;
        dut_rs2_data_in = 32'd10;

        @(posedge clk); #1;

        assert(dut_rd_data_out == 32'd14)
        else begin
            $display("ERROR: OR failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST 5 : XOR
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST XOR", $time());

        @(posedge clk); #1;

        dut_instruction_in.op = op::XOR;

        dut_rs1_data_in = 32'd12;
        dut_rs2_data_in = 32'd10;

        @(posedge clk); #1;

        assert(dut_rd_data_out == 32'd6)
        else begin
            $display("ERROR: XOR failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST 6 : SLL
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST SLL", $time());

        @(posedge clk); #1;

        dut_instruction_in.op = op::SLL;

        dut_rs1_data_in = 32'd3;
        dut_rs2_data_in = 32'd2;

        @(posedge clk); #1;

        assert(dut_rd_data_out == 32'd12)
        else begin
            $display("ERROR: SLL failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST 7 : SRL
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST SRL", $time());

        @(posedge clk); #1;

        dut_instruction_in.op = op::SRL;

        dut_rs1_data_in = 32'd16;
        dut_rs2_data_in = 32'd2;

        @(posedge clk); #1;

        assert(dut_rd_data_out == 32'd4)
        else begin
            $display("ERROR: SRL failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST 8 : SRA
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST SRA", $time());

        @(posedge clk); #1;

        dut_instruction_in.op = op::SRA;

        dut_rs1_data_in = -32'sd16;
        dut_rs2_data_in = 32'd2;

        @(posedge clk); #1;

        assert($signed(dut_rd_data_out) == -32'sd4)
        else begin
            $display("ERROR: SRA failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST 9 : SLT
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST SLT", $time());

        @(posedge clk); #1;

        dut_instruction_in.op = op::SLT;

        dut_rs1_data_in = -32'sd1;
        dut_rs2_data_in = 32'd1;

        @(posedge clk); #1;

        assert(dut_rd_data_out == 32'd1)
        else begin
            $display("ERROR: SLT failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST 10 : SLTU
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST SLTU", $time());

        @(posedge clk); #1;

        dut_instruction_in.op = op::SLTU;

        dut_rs1_data_in = 32'hffffffff;
        dut_rs2_data_in = 32'd1;

        @(posedge clk); #1;

        assert(dut_rd_data_out == 32'd0)
        else begin
            $display("ERROR: SLTU failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST 11 : ADD OVERFLOW
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST ADD OVERFLOW", $time());

        @(posedge clk); #1;

        dut_instruction_in.op = op::ADD;

        dut_rs1_data_in = 32'hffffffff;
        dut_rs2_data_in = 32'h1;

        @(posedge clk); #1;

        assert(dut_rd_data_out == 32'h00000000)
        else begin
            $display("ERROR: ADD overflow failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST 12 : BEQ TAKEN
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST BEQ TAKEN", $time());

        @(posedge clk); #1;

        dut_instruction_in.op        = op::BEQ;
        dut_instruction_in.immediate = 32'd16;

        dut_program_counter_in = 32'h00000100;

        dut_rs1_data_in = 32'd5;
        dut_rs2_data_in = 32'd5;

        @(posedge clk); #1;

        assert(dut_jump_address_out == 32'h00000110)
        else begin
            $display("ERROR: BEQ target failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST 13 : BEQ NOT TAKEN
        // ----------------------------------------------------------------------------------------

        $display("------------------------------ (%6d ns) TEST BEQ NOT TAKEN", $time());

        @(posedge clk); #1;

        dut_instruction_in.op        = op::BEQ;
        dut_instruction_in.immediate = 32'd16;

        dut_program_counter_in = 32'h00000100;

        dut_rs1_data_in = 32'd5;
        dut_rs2_data_in = 32'd7;

        @(posedge clk); #1;

        assert(dut_next_pc_out == 32'h00000104)
        else begin
            $display("ERROR: BEQ next_pc failed");
            error_count++;
        end;

        // ----------------------------------------------------------------------------------------
        // TEST DONE
        // ----------------------------------------------------------------------------------------

        @(posedge clk);
        @(posedge clk);

        print_test_done();

        $finish();
    end

    // --------------------------------------------------------------------------------------------
    // reset helper

    function void reset_module_inputs();

        dut_instruction_in        = '0;

        dut_program_counter_in    = 0;

        dut_rs1_data_in           = 0;
        dut_rs2_data_in           = 0;

        dut_jump_address_in       = 0;

        dut_status_forwards_in    = pipeline_status::BUBBLE;
        dut_status_backwards_in   = pipeline_status::READY;

    endfunction

    // --------------------------------------------------------------------------------------------

    function void perform_rst();

        @(negedge clk); #1;

        rst = 1;

        reset_module_inputs();

        @(posedge clk); #1;
        @(posedge clk); #1;

        rst = 0;

    endfunction

    // --------------------------------------------------------------------------------------------
    // print helper functions

    function void print_test_done();

        if (error_count != 0) begin
            $display("\033[0;31m");
            $display("Some test(s) failed! (# Errors: %4d)", error_count);
        end
        else begin
            $display("\033[0;32m");
            $display("All tests passed! (# Errors: %4d)", error_count);
        end

        $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        $display("!!!!!!!!!!!!!!!!!!!! TEST DONE !!!!!!!!!!!!!!!!!!!!");
        $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");

        $display("\033[0m");

    endfunction

endmodule