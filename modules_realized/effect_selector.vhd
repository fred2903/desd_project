----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/29/2024 10:12:03 AM
-- Design Name: 
-- Module Name: effect_selector - Behavioral
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
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity effect_selector is
    generic(
        JOYSTICK_LENGHT  : integer := 10    -- 10 bit for X and Y axis
    );
    Port (
        clk : in STD_LOGIC;
        resetn : in STD_LOGIC;
        effect : in STD_LOGIC;
        jstck_x : in STD_LOGIC_VECTOR(JOYSTICK_LENGHT-1 downto 0);
        jstck_y : in STD_LOGIC_VECTOR(JOYSTICK_LENGHT-1 downto 0);
        volume : out STD_LOGIC_VECTOR(JOYSTICK_LENGHT-1 downto 0);
        balance : out STD_LOGIC_VECTOR(JOYSTICK_LENGHT-1 downto 0);
        gain : out STD_LOGIC_VECTOR(JOYSTICK_LENGHT-1 downto 0);
        delay : out STD_LOGIC_VECTOR(JOYSTICK_LENGHT-1 downto 0)
    );
end effect_selector;


architecture Behavioral of effect_selector is

--internal register
signal volume_reg  : STD_LOGIC_VECTOR(JOYSTICK_LENGHT-1 downto 0) := (others => '0');
signal balance_reg : STD_LOGIC_VECTOR(JOYSTICK_LENGHT-1 downto 0) := (others => '0');
signal gain_reg    : STD_LOGIC_VECTOR(JOYSTICK_LENGHT-1 downto 0) := (others => '0');
signal delay_reg   : STD_LOGIC_VECTOR(JOYSTICK_LENGHT-1 downto 0) := (others => '0');

begin

process(clk)
begin
    if rising_edge(clk) then
        
     if resetn='0' then
            volume_reg  <= (others => '0');
            balance_reg <= (others => '0');
            gain_reg    <= (others => '0');
            delay_reg   <= (others => '0');
     else

       --reverb
       if effect='1' then
        gain_reg  <= jstck_x;
        delay_reg <= jstck_y;

       --volume and balance      
       else
       balance_reg  <= jstck_x;
       volume_reg <= jstck_y;

        end if;

      end if;

    end if;
 end process;
 
--output
    volume  <= volume_reg;
    balance <= balance_reg;
    gain    <= gain_reg;
    delay   <= delay_reg;



end Behavioral;
