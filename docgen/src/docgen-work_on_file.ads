-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2001-2004                       --
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

--  This package is the part of the Docgen tool responsable for the
--  processing of the program structure information for the source file
--  list passed by the procedure Docgen.

with Glide_Kernel;

package Docgen.Work_On_File is

   procedure Process_Files
     (B                : access Docgen_Backend.Backend'Class;
      Source_File_List : in out Type_Source_File_Table.HTable;
      Kernel           : access Glide_Kernel.Kernel_Handle_Record'Class;
      Options          : Docgen.All_Options);
   --  Process all files from Source_File_List, and generate their
   --  documentation.

end Docgen.Work_On_File;
