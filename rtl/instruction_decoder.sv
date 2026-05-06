/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: instruction_decoder.sv
 */



module instruction_decoder (
    input  logic [31:0]   instruction_in,
    output instruction::t instruction_out
);

logic [6:0] opcode ;
assign opcode = instruction_in[6:0];
logic [2:0] funct3 ;
assign funct3 = instruction_in[14:12];
logic [6:0] funct7 ;
assign funct7 = instruction_in[31:25];

logic [4:0] rd ; 
assign rd = instruction_in[11:7];
logic [4:0] rs1 ;
assign rs1 = instruction_in[19:15];
logic [4:0] rs2 ;
assign rs2 = instruction_in[24:20];

logic [11:0] csr ;
assign csr = instruction_in[31:20];
logic [31:0] immediate ;
assign immediate = instruction_in[31:0];

always_comb begin 


    // ---------- DEFAULT ----------
    instruction_out = '0;
    instruction_out.op = op::ILLEGAL;

    case (opcode)

        //----------R-Type Instructions----------
        7'b0110011: begin
            case (funct7)

                7'b0000000: begin
                    case (funct3)
                        3'b000: instruction_out.op = op::ADD;
                        3'b001: instruction_out.op = op::SLL;
                        3'b010: instruction_out.op = op::SLT;
                        3'b011: instruction_out.op = op::SLTU;
                        3'b100: instruction_out.op = op::XOR;
                        3'b101: instruction_out.op = op::SRL;
                        3'b110: instruction_out.op = op::OR;
                        3'b111: instruction_out.op = op::AND;
                        default: instruction_out.op = op::ILLEGAL;
                    endcase
                end

                7'b0100000: begin
                    case (funct3)
                        3'b000: instruction_out.op = op::SUB;
                        3'b101: instruction_out.op = op::SRA;
                        default: instruction_out.op = op::ILLEGAL;
                    endcase
                end

                default: instruction_out.op = op::ILLEGAL;

            endcase

            if (instruction_out.op != op::ILLEGAL) begin
                instruction_out.rd_address  = rd;
                instruction_out.rs1_address = rs1;
                instruction_out.rs2_address = rs2;
            end

        end

       //----------I-Type Instructions----------
        7'b0010011: begin

            case (funct3)
                3'b000: instruction_out.op = op::ADDI;
                3'b010: instruction_out.op = op::SLTI;
                3'b011: instruction_out.op = op::SLTIU;
                3'b100: instruction_out.op = op::XORI;
                3'b110: instruction_out.op = op::ORI;
                3'b111: instruction_out.op = op::ANDI;

                3'b001: begin
                    instruction_out.op = (funct7 == 7'b0000000) ? op::SLLI : op::ILLEGAL;
                end

                3'b101: begin
                    instruction_out.op = (funct7 == 7'b0000000) ? op::SRLI : 
                                         (funct7 == 7'b0100000) ? op::SRAI : op::ILLEGAL;
                end
                
                default: instruction_out.op = op::ILLEGAL;
            endcase

            if(instruction_out.op != op::ILLEGAL) begin
                instruction_out.rd_address  = rd;
                instruction_out.rs1_address = rs1;
                
                // Immediate generation based on instruction type
                if (funct3 == 3'b001 || funct3 == 3'b101) begin
                    instruction_out.immediate = {27'd0, instruction_in[24:20]};
                end
                else begin
                    instruction_out.immediate = {{20{instruction_in[31]}}, instruction_in[31:20]};
                end
            end

        end

        //----------Store-Type Instructions----------
        7'b0100011: begin


            case (funct3)
                3'b000: instruction_out.op = op::SB;
                3'b001: instruction_out.op = op::SH;
                3'b010: instruction_out.op = op::SW;
                default: instruction_out.op = op::ILLEGAL;
            endcase

            if(instruction_out.op != op::ILLEGAL) begin
                instruction_out.rs1_address = rs1;
                instruction_out.rs2_address = rs2;

                instruction_out.immediate = {
                    {20{instruction_in[31]}},
                    instruction_in[31:25],
                    instruction_in[11:7]
                };
            end
        
        end

        //----------Load-Type Instructions----------
        7'b0000011: begin


            case (funct3)
                3'b000: instruction_out.op = op::LB;
                3'b001: instruction_out.op = op::LH;
                3'b010: instruction_out.op = op::LW;
                3'b100: instruction_out.op = op::LBU;
                3'b101: instruction_out.op = op::LHU;
                default: instruction_out.op = op::ILLEGAL;
            endcase

            if(instruction_out.op != op::ILLEGAL)begin
                
                instruction_out.rd_address  = rd;
                instruction_out.rs1_address = rs1;

                instruction_out.immediate = {{20{instruction_in[31]}}, instruction_in[31:20]};

            end
        
        end

        //----------Branch-Type Instructions----------
        7'b1100011: begin


            case (funct3)
                3'b000: instruction_out.op = op::BEQ;
                3'b001: instruction_out.op = op::BNE;
                3'b100: instruction_out.op = op::BLT;
                3'b101: instruction_out.op = op::BGE;
                3'b110: instruction_out.op = op::BLTU;
                3'b111: instruction_out.op = op::BGEU;
                default: instruction_out.op = op::ILLEGAL;
            endcase

            if(instruction_out.op != op::ILLEGAL) begin

                instruction_out.rs1_address = rs1;
                instruction_out.rs2_address = rs2;

                instruction_out.immediate = {
                    {19{instruction_in[31]}},
                    instruction_in[31],
                    instruction_in[7],
                    instruction_in[30:25],
                    instruction_in[11:8],
                    1'b0
                };

                end
        
        end

        //----------U-Type Instructions----------
        7'b0110111: begin // LUI
            instruction_out.rd_address = rd;
            instruction_out.immediate = {instruction_in[31:12], 12'b0};
            instruction_out.op = op::LUI;
        
        end

        7'b0010111: begin // AUIPC
            instruction_out.rd_address = rd;
            instruction_out.immediate = {instruction_in[31:12], 12'b0};
            instruction_out.op = op::AUIPC;
        
        end

        //----------J-Type Instructions----------
        7'b1101111: begin // JAL
            instruction_out.rd_address = rd;

            instruction_out.immediate = {
                {11{instruction_in[31]}},
                instruction_in[31],
                instruction_in[19:12],
                instruction_in[20],
                instruction_in[30:21],
                1'b0
            };

            instruction_out.op = op::JAL;
        
        end

        //----------JALR----------
        7'b1100111: begin
            instruction_out.rd_address  = rd;
            instruction_out.rs1_address = rs1;

            instruction_out.immediate = {{20{instruction_in[31]}}, instruction_in[31:20]};

            instruction_out.op = op::JALR;
        
        end

        //----------FENCE Instructions----------
        7'b0001111: begin

            case (funct3)
                3'b000: instruction_out.op = op::FENCE;
                3'b001: instruction_out.op = op::FENCE_I;
                default: instruction_out.op = op::ILLEGAL;
            endcase

            if(instruction_out.op != op::ILLEGAL) begin
                instruction_out.rd_address  = rd;
                instruction_out.rs1_address = rs1;

                instruction_out.immediate = {{20{instruction_in[31]}}, instruction_in[31:20]};
            end
        
        end
        //----------SYSTEM Instructions----------
        7'b1110011: begin

            case (funct3)

                // ---------- ECALL / EBREAK / MRET / WFI ----------
                3'b000: begin
                    if (rd != 5'd0 || rs1 != 5'd0) begin
                        instruction_out.op = op::ILLEGAL;
                    end else begin
                        case (csr)
                            12'h000: instruction_out.op = op::ECALL;
                            12'h001: instruction_out.op = op::EBREAK;
                            12'h302: instruction_out.op = op::MRET;
                            12'h105: instruction_out.op = op::WFI;
                            default: instruction_out.op = op::ILLEGAL;
                        endcase
                    end
                end

                // ---------- CSR (register) ----------
                3'b001: instruction_out.op = op::CSRRW;
                3'b010: instruction_out.op = op::CSRRS;
                3'b011: instruction_out.op = op::CSRRC;

                // ---------- CSR (immediate) ----------
                3'b101: instruction_out.op = op::CSRRWI;
                3'b110: instruction_out.op = op::CSRRSI;
                3'b111: instruction_out.op = op::CSRRCI;
                
                default: instruction_out.op = op::ILLEGAL;

            endcase

            if(instruction_out.op != op::ILLEGAL) begin
                
                // rd is used by all CSR instructions
                instruction_out.rd_address = rd;
                
                // CSR address for all CSR instructions
                instruction_out.csr = csr::t'(csr);
                
                // Handle operands based on instruction type
                case (funct3)
                    // CSR register instructions: use rs1 as source register
                    3'b001, 3'b010, 3'b011: begin
                        instruction_out.rs1_address = rs1;
                    end
                    
                    // CSR immediate instructions: use rs1 field as 5-bit immediate (zimm)
                    3'b101, 3'b110, 3'b111: begin
                        instruction_out.immediate = {27'd0, rs1};  // Zero-extend 5-bit immediate
                        instruction_out.rs1_address = 5'd0;        // No source register
                    end
                    
                    // ECALL/EBREAK/MRET/WFI: no operands needed
                    default: begin
                        instruction_out.rs1_address = 5'd0;
                    end
                endcase

            end


        end 

        default: begin
            instruction_out.op = op::ILLEGAL;
        end

    endcase

end

endmodule
