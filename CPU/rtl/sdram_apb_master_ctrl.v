`timescale 1ns / 1ps

module sdram_apb_master_ctrl (
    input             clk,
    input             rstb,
    input             pready,
    input             rw_valid,
    // APB Master -> Slave
    output reg        pena,
    output reg        psel
);

localparam [1:0] m_idle = 2'd0;
localparam [1:0] m_setup = 2'd1;
localparam [1:0] m_access = 2'd2;


reg [1:0] m_state, m_state_n;

//next state
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        m_state <= m_idle;
    end else begin           
        m_state <= m_state_n;
    end
end

//current state
always @(*) begin
    m_state_n = m_state;
    case (m_state)
        m_idle: if (rw_valid) m_state_n = m_setup; 
        m_setup: m_state_n = m_access;
        m_access: if (pready) m_state_n = m_idle;
    endcase
end

//Output logic
always @(*) begin
    psel = 1'b0;
    pena = 1'b0;
    case (m_state)
        m_idle: begin
            psel = 1'b0;
            pena = 1'b0;
        end
        m_setup: begin
            psel = 1'b1;
            pena = 1'b0;
        end
        m_access: begin
            psel = 1'b1;
            pena = 1'b1;
        end
    endcase
end

endmodule
