-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                        Copyright (C) 2002                         --
--                            ACT-Europe                             --
--                                                                   --
-- GPS is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

package body Codefix is

   ----------------------------------------------------------------------------
   --  type Dynamic_String
   ----------------------------------------------------------------------------

   ------------
   -- Affect --
   ------------

   procedure Assign (This : in out Dynamic_String; Value : String) is
   begin
      Free (This);
      This := new String'(Value);
   end Assign;

   ------------
   -- Affect --
   ------------

   procedure Assign (This : in out Dynamic_String; Value : Dynamic_String) is
   begin
      Free (This);
      This := new String'(Value.all);
   end Assign;

   --------------
   -- Get_Line --
   --------------

   procedure Get_Line (This : in out Dynamic_String) is
   begin
      Get_Line (Standard_Input, This);
   end Get_Line;

   --------------
   -- Get_Line --
   --------------

   procedure Get_Line (File : File_Type; This : in out Dynamic_String) is
      Len          : Natural;
      Current_Size : Natural := 128;
   begin
      loop
         declare
            Buffer : String (1 .. Current_Size);
         begin
            Get_Line (File, Buffer, Len);
            Free (This);
            This := new String'(Buffer (1 .. Len));
            if Len < Current_Size then return; end if;
         end;
         Current_Size := Current_Size * 2;
      end loop;
   end Get_Line;

   --------------
   -- Put_Line --
   --------------

   procedure Put_Line (This : Dynamic_String) is
   begin
      Put_Line (Standard_Output, This);
   end Put_Line;

   --------------
   -- Put_Line --
   --------------

   procedure Put_Line (File : File_Type; This : Dynamic_String) is
   begin
      Put_Line (File, This.all);
   end Put_Line;

end Codefix;
