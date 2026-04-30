module sdram_master_command_cdc(

);



//-------cmdwe_req sync (clk1 domain)----------------------
reg [1:0] cmdwe_req_r;
always @(posedge clk1 or negedge rstb) begin
    if (!rstb)
        cmdwe_req_r <= 2'b00;
    else
        cmdwe_req_r <= {cmdwe_req_r[0], cmdwe_req};
end

//-------cmdwdata_cdc (clk1 domain)----------------------
always @(posedge clk1 or negedge rstb) begin
    if (!rstb)
        cmdwdata_cdc <= 25'h0;
    else if (cmdwe_req_signal)
        cmdwdata_cdc <= cmdwdata_r;
end

//-------cmdwe_req_seen_r (clk1 domain)----------------------
always @(posedge clk1 or negedge rstb) begin
    if (!rstb)
        cmdwe_req_seen_r <= 1'b0;
    else if (cmdwe_req_signal)
        cmdwe_req_seen_r <= 1'b1;
end


//-------cmdre_req (clk1 domain)----------------------
always @(posedge clk1 or negedge rstb) begin
    if (!rstb)
        cmdre_req <= 1'b0;
    else if (cmdre)
        cmdre_req <= 1'b1;
end



//-------cmd_present (clk1 domain)----------------------
always @(posedge clk1 or negedge rstb) begin
    if (!rstb)
        cmd_present <= 1'b0;
    else if (cmdwe_req_signal)
        cmd_present <= 1'b1;
    else if (cmdre)
        cmd_present <= 1'b0;
end

assign cmd_data = cmdwdata_cdc;
assign cmdempty = !cmd_present;
assign cmdfull  = cmdwe_req || cmdre_req_ack;