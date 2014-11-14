------------------------------------------------------------------------------
--                              C O D E P E E R                             --
--                                                                          --
--                     Copyright (C) 2008-2014, AdaCore                     --
--                                                                          --
-- This is free software;  you can redistribute it  and/or modify it  under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
--                                                                          --
-- The CodePeer technology was originally developed by SofCheck, Inc.       --
------------------------------------------------------------------------------

with Ada.Directories; use Ada.Directories;

package body BT.Xml is

   function Xml_File_Name
     (Output_Dir     : String;
      File_Path      : String;
      For_Backtraces : Boolean) return String
   is
      Xml_Directory : constant String := Output_Dir & "/bts/";
      Xml_File_Name : constant String :=
        Xml_Directory & Simple_Name (File_Path);

   begin
      if not Exists (Xml_Directory) then
         Create_Directory (Xml_Directory);
      end if;

      if For_Backtraces then
         return Xml_File_Name & "_bts.xml";
      else
         return Xml_File_Name & "_vals.xml";
      end if;
   end Xml_File_Name;

   --------------------------------------
   -- Inspection_Output_Directory_Name --
   --------------------------------------

   function Inspection_Output_Directory_Name
     (XML_File_Name : String) return String is
   begin
      return
        Ada.Directories.Containing_Directory
          (Ada.Directories.Containing_Directory (XML_File_Name));
   end Inspection_Output_Directory_Name;

end BT.Xml;
