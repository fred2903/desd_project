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
    Port ( 
        s_axis_tready : OUT STD_LOGIC;
        s_axis_tdata : IN STD_LOGIC_VECTOR(CHANNEL_LENGHT-1 DOWNTO 0);
        s_axis_tlast : IN STD_LOGIC;
        s_axis_tvalid : IN STD_LOGIC;
        m_axis_tvalid : OUT STD_LOGIC;
        m_axis_tdata : OUT STD_LOGIC_VECTOR(CHANNEL_LENGHT-1 DOWNTO 0);
        m_axis_tready : IN STD_LOGIC;
        m_axis_tlast : OUT STD_LOGIC;
        enable_filter: IN STD_LOGIC;
        aclk : IN STD_LOGIC;
        aresetn : IN STD_LOGIC
    );
end moving_average;

architecture Behavioral of moving_average is
    
begin

end Behavioral;
