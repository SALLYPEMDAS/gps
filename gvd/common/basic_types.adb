-----------------------------------------------------------------------
--                   GVD - The GNU Visual Debugger                   --
--                                                                   --
--                      Copyright (C) 2000-2003                      --
--                              ACT-Europe                           --
--                                                                   --
-- GVD is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this library; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with GNAT.OS_Lib; use GNAT.OS_Lib;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Unchecked_Deallocation;

package body Basic_Types is

   ----------
   -- Free --
   ----------

   procedure Free (Ar : in out String_Array) is
   begin
      for A in Ar'Range loop
         Free (Ar (A));
      end loop;
   end Free;

   procedure Free (Ar : in out Argument_List) is
   begin
      for A in Ar'Range loop
         Free (Ar (A));
      end loop;
   end Free;

   procedure Free (Ar : in out String_Array_Access) is
   begin
      if Ar /= null then
         Free (Ar.all);
         Unchecked_Free (Ar);
      end if;
   end Free;

   --------------
   -- Is_Equal --
   --------------

   function Is_Equal
     (List1, List2   : Argument_List;
      Case_Sensitive : Boolean := True) return Boolean is
   begin
      if List1'Length /= List2'Length then
         return False;

      else
         declare
            L1 : Argument_List := List1;
            L2 : Argument_List := List2;
         begin
            for A in L1'Range loop
               for B in L2'Range loop
                  if L2 (B) /= null and then
                    ((Case_Sensitive and then L1 (A).all = L2 (B).all)
                     or else
                     (not Case_Sensitive
                      and then To_Lower (L1 (A).all) =
                               To_Lower (L2 (B).all)))
                  then
                     L1 (A) := null;
                     L2 (B) := null;
                     exit;
                  end if;
               end loop;
            end loop;

            return L1 = (L1'Range => null)
              and then L2 = (L2'Range => null);
         end;
      end if;
   end Is_Equal;

   --------------
   -- Contains --
   --------------

   function Contains
     (List           : GNAT.OS_Lib.Argument_List;
      Str            : String;
      Case_Sensitive : Boolean := True) return Boolean is
   begin
      if not Case_Sensitive then
         declare
            S : constant String := To_Lower (Str);
         begin
            for L in List'Range loop
               if To_Lower (List (L).all) = S then
                  return True;
               end if;
            end loop;
         end;
      else
         for L in List'Range loop
            if List (L).all = Str then
               return True;
            end if;
         end loop;
      end if;

      return False;
   end Contains;

   ------------------
   -- Add_And_Grow --
   ------------------

   procedure Add_And_Grow (List         : in out Arr_Access;
                           Last_In_List : in out Index;
                           Item         : Data;
                           Minimal_Inc  : Index := 1)
   is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (Arr, Arr_Access);
      Inc : Index;
      Tmp : Arr_Access;
   begin
      if List = null then
         List := new Arr
           (Index'First .. Index'First + Index'Max (Minimal_Inc, 20));
         Last_In_List := List'First;
      elsif Last_In_List > List'Last then
         Inc := Index'Max (Minimal_Inc, List'Length);
         Tmp := new Arr (List'First .. List'Last + Inc);
         Tmp (List'Range) := List.all;
         Unchecked_Free (List);
         List := Tmp;
      end if;

      List (Last_In_List) := Item;
      Last_In_List := Index'Succ (Last_In_List);
   end Add_And_Grow;

end Basic_Types;
