/*

Prelude
-A tribute to "Overture"
Written by Jared De Blander in December of 2024

This is designed to be a simple 8 bit RISC CPU inspired by Overture from Turing
Complete

*/
module prelude(
    input logic clk,
    input logic reset,
    input logic [7:0] rio_in,
    output logic [7:0] rio_out,
);

    logic [7:0] pc; // program counter
    logic [7:0] ir; // instruction register
    logic [7:0] next_pc; // next program counter

    // alu result
    logic [7:0] alu_out;

    // branching signals
    logic condition_result;
    logic [7:0] r0_out; // register 0 output
    logic [7:0] r3_out; // register 3 output

    // register file signals
    logic write_enable;
    logic [2:0] src_a;
    logic [2:0] src_b;
    logic [2:0] dst;
    logic [7:0] in;
    logic [7:0] out_a;
    logic [7:0] out_b;

    // instantiate modules
    registers r_file(
        .src_a(src_a),
        .src_b(src_b),
        .dst(dst),
        .write_enable(write_enable),
        .in(in),
        .clk(clk),
        .out_a(out_a),
        .out_b(out_b),
        .r0_out(r0_out),
        .r3_out(r3_out),
        .rio_out(rio_out)
    );

    rom instruction_rom (
        .address(pc),
        .data(ir)
    );

    alu alu (
        .alu_op(ir[5:0]),
        .in_a(out_a),
        .in_b(out_b),
        .out(alu_out)
    );

    conditions condition_engine (
        .r3(r3_out),
        .condition(ir[2:0]),
        .result(condition_result)
    );

    // calculate our incrementing program counter and send control signals
    // to the functional units
    always_comb begin
        next_pc = pc + 1;

        casez (ir)
            // immediate
            8'b00zzzzzz: begin
                dst = 3'b000;
                in = {2'b00, ir[5:0]};
                write_enable = 1'b1;

            end

            // calculate
            8'b01zzzzzz: begin
                dst = 3'b011;
                in = alu_out;
                write_enable = 1'b1;
            end

            // copy
            8'b10zzzzzz: begin
                src_a = ir[5:3];
                dst = ir[2:0];
                in = out_a;
                write_enable = 1'b1;
            end

            // branch
            8'b11zzzzzz: begin
                dst = 3'b000;
                write_enable = 1'b0;
            end
        endcase
    end

    // advance the program counter, branching
    // when appropriate
    always_ff @(posedge clk) begin
        // when reset is high, reset the program counter
        if (reset) pc <= 8'b00000000;
        else begin
            if ((ir[7:6] == 2'b11) & condition_result) pc <= r0_out;
            else pc <= next_pc;
        end
    end
endmodule


/*

Conditional branching unit for Prelude

Condition bits for branch instructions are as follows:

---------------|-----------|------------------------------
Condition      |           |
bits           | Condition | Notes
---------------|-----------|------------------------------
           000 | Never     | No op, never take branch
           001 | R3 ==  0  |
           010 | R3 < 0    | signed
           011 | R3 <= 0   | signed
           100 | Always    |
           101 | R3 != 0   |
           110 | R3 >= 0   | signed
           111 | R3 > 0    | signed
---------------|-----------|------------------------------

...or all of r3 bits together then invert to get if all bits are zero
logic r_eq_zero = ~|r3;

...check if top bit set for less than zero
logic r_lt_zero = r3[7];

...check if top bit not set and any other bit set for greater than zero
logic r_gt_zero = (r3[7] == 1'b0) & ~(~|r3);

*/


`define BRN      3'b000
`define BZ       3'b001
`define BLT      3'b010
`define BLE      3'b011
`define BRA      3'b100
`define BNZ      3'b101
`define BGE      3'b110
`define BGT      3'b111

module conditions(
    input logic [7:0] r3,
    input logic [2:0] condition,
    output logic result
);
    always_comb begin
        case (condition)
            `BRN: result = 1'b0;
            `BZ:  result = (~|r3);
            `BLT: result = (r3[7]);
            `BLE: result = (~|r3) | (r3[7]);
            `BRA: result = 1'b1;
            `BNZ: result = ~(~|r3);
            `BGE: result = (~|r3) | ((r3[7] == 1'b0) & ~(~|r3));
            `BGT: result = ((r3[7] == 1'b0) & ~(~|r3));
        endcase
    end

endmodule

/*

The Arithmetic Logic Unit (ALU) for Prelude

ALU operations for Prelude are defined as follows:

----------|-----------|----------------------------------------
  ALU op  |           |
  bits    | Operation | Description
----------|-----------|----------------------------------------
   000000 | OR        | out = in_a or in_b
   000001 | NAND      | out = ~(in_a and in_b)
   000010 | NOR       | out = ~(in_a or in_b)
   000011 | AND       | out = in_a and in_b
   000100 | ADD       | out = in_a + in_b
   000101 | SUB       | out = in_a - in_b
   000110 | XOR       | out = in_a ^ in_b, Prelude specific
   000111 | SHL       | out = in_a << in_b, Prelude specific
----------|-----------|----------------------------------------

*/

`define ALU_OR      6'b000000
`define ALU_NAND    6'b000001
`define ALU_NOR     6'b000010
`define ALU_AND     6'b000011
`define ALU_ADD     6'b000100
`define ALU_SUB     6'b000101
`define ALU_XOR     6'b000110
`define ALU_SHL     6'b000111

module alu (
    input logic [5:0] alu_op,
    input logic [7:0] in_a,
    input logic [7:0] in_b,
    output logic [7:0] out
);
    always_comb begin
        casez (alu_op)
            `ALU_OR:     out = in_a | in_b;
            `ALU_NAND:   out = ~(in_a & in_b);
            `ALU_NOR:    out = ~(in_a | in_b);
            `ALU_AND:    out = in_a & in_b;
            `ALU_ADD:    out = in_a + in_b;
            `ALU_SUB:    out = in_a - in_b;
            `ALU_XOR:    out = in_a ^ in_b;
            `ALU_SHL:    out = in_a << in_b;
            default: out = 8'b0;
        endcase
    end
endmodule

/*

Prelude's register file

*/

module registers(
    input logic [2:0] src_a,
    input logic [2:0] src_b,
    input logic [2:0] dst,
    input logic write_enable,
    input logic [7:0] in,
    input logic clk,
    output logic [7:0] out_a,
    output logic [7:0] out_b,
    output logic [7:0] r0_out,
    output logic [7:0] r3_out,
    output logic [7:0] rio_out
);
    logic [7:0] register_file [7:0];

    always_comb begin
        // hard wire special output registers
        r0_out = register_file[0];
        r3_out = register_file[3];
        rio_out = register_file[7];


        if (src_a == 3'b111) begin
            // when RIO is specified as a source, output the value of the `in` signal
            out_a = in;
        end else begin
            // output the value of the selected registers
            out_a = register_file[src_a];
        end

        if (src_b == 3'b111) begin
            // when RIO is specified as a source, output the value of the `in` signal
            out_b = in;
        end else begin
            // output the value of the selected registers
            out_b = register_file[src_b];
        end
    end

    always_ff @(posedge clk) begin
        if (write_enable)
            register_file[dst] <= in;
    end

endmodule

/*

Read only memory uses rom.txt to generate the program ROM for Prelude

*/

module rom (
    input logic [7:0] address,
    output logic [7:0] data
);
    logic [7:0] rom_contents [0:255];

    // load our program ROM from rom.txt
    initial begin
        $readmemb("rom.txt", rom_contents);
    end

    always_comb begin
        data = rom_contents[address];
    end
endmodule