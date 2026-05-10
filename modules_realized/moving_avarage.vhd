----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 10.05.2021 19:20:17
-- Design Name: 
-- Module Name: moving_average_filter - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity moving_average is
    Generic(
        LOG2_LEN: POSITIVE := 5;            -- Perform the average over 2^LOG2_LEN samples
        CHANNEL_LENGHT  : integer := 24     -- 3 Byte for AXIS audio I2S
    );
    Port( 
        s_axis_tready       : OUT STD_LOGIC;
        s_axis_tdata        : IN STD_LOGIC_VECTOR(CHANNEL_LENGHT-1 DOWNTO 0);
        s_axis_tlast        : IN STD_LOGIC;
        s_axis_tvalid       : IN STD_LOGIC;
        m_axis_tvalid       : OUT STD_LOGIC;
        m_axis_tdata        : OUT STD_LOGIC_VECTOR(CHANNEL_LENGHT-1 DOWNTO 0);
        m_axis_tready       : IN STD_LOGIC;
        m_axis_tlast        : OUT STD_LOGIC;
        enable_filter       : IN STD_LOGIC;
        aclk                : IN STD_LOGIC;
        aresetn             : IN STD_LOGIC
    );
end moving_average;
architecture Behavioral of moving_average is

    -- FSM States
    type state_type is (IDLE, COMPUTE, SEND);
    signal state : state_type := IDLE;

    -- Buffer (Inferred RAM)
    type ram_type is array (0 to 2**LOG2_LEN - 1) of SIGNED(CHANNEL_LENGHT-1 downto 0);
    signal ram_buffer : ram_type := (others => (others => '0'));
    signal ptr : unsigned(LOG2_LEN-1 downto 0) := (others => '0');

    -- internal registers
    signal tdata_reg     : SIGNED(CHANNEL_LENGHT-1 downto 0);
    signal tlast_reg     : std_logic;
    signal old_sample    : SIGNED(CHANNEL_LENGHT-1 downto 0);
    signal sum_reg       : SIGNED(CHANNEL_LENGHT + LOG2_LEN - 1 downto 0) := (others => '0');
    
    -- Output registers
    signal tdata_out_reg : std_logic_vector(CHANNEL_LENGHT-1 downto 0);
    signal tlast_out_reg : std_logic;

begin
-----------------------------------------------------
    -- Output Assignments
    -----------------------------------------------------
    
    with state select s_axis_tready <=
        '1' when IDLE,
        '0' when others;

    with state select m_axis_tvalid <=
        '1' when SEND,
        '0' when others;

    with state select m_axis_tdata <=
        tdata_out_reg when SEND,
        (others => '0') when others;

    with state select m_axis_tlast <=
        tlast_out_reg when SEND,
        '0' when others;

    -----------------------------------------------------
    --  FSM and Logic
    -----------------------------------------------------
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state         <= IDLE;
                sum_reg       <= (others => '0');
                ptr           <= (others => '0');
                tdata_out_reg <= (others => '0');
                tlast_out_reg <= '0';
            else
                case state is

                    when IDLE =>
                        if s_axis_tvalid = '1' then
                            -- Leggiamo il valore vecchio per preparare il calcolo
                            old_sample <= ram_buffer(to_integer(ptr));
                            tdata_reg  <= signed(s_axis_tdata);
                            tlast_reg  <= s_axis_tlast;
                            state      <= COMPUTE;
                        end if;

                    when COMPUTE =>
                        --  RAM to save the new sample
                        ram_buffer(to_integer(ptr)) <= tdata_reg;
                        
                        -- 2. sum (Resize is used to avoid overflow, we need to make sure the sum can hold the maximum possible value of 2^LOG2_LEN samples)
                        sum_reg <= sum_reg + resize(tdata_reg, sum_reg'length) - resize(old_sample, sum_reg'length);
                        
                        -- 3. pointer update
                        ptr <= ptr + 1;
                        
                        -- 4. if the filter is enabled, we perform the division by shifting right by LOG2_LEN (equivalent to dividing by 2^LOG2_LEN), otherwise we just pass the input through
                        if enable_filter = '1' then
                            -- this is a simple arithmetic to compute the average, we take the sum and shift it right by LOG2_LEN to divide by the number of samples
                            tdata_out_reg <= std_logic_vector(sum_reg(sum_reg'high downto LOG2_LEN));
                        else
                            tdata_out_reg <= std_logic_vector(tdata_reg);
                        end if;
                        
                        tlast_out_reg <= tlast_reg;
                        state         <= SEND;

                    when SEND =>
                        if m_axis_tready = '1' then
                            state <= IDLE;
                        end if;

                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end Behavioral;