-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2009, AdaCore                   --
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

with GNAT.Regpat;       use GNAT.Regpat;

with Glib;
with Gdk.Color;
with Gdk.Pixbuf;        use Gdk.Pixbuf;
with Gtk.Tree_Model;    use Gtk.Tree_Model;
with Gtk.Tree_Store;    use Gtk.Tree_Store;

with GNATCOLL.VFS;

with Basic_Types;       use Basic_Types;
with GPS.Editors;       use GPS.Editors;
with GPS.Kernel;        use GPS.Kernel;
with GPS.Kernel.Styles; use GPS.Kernel.Styles;

package GPS.Location_Model is

   --  The following list must be synchronized with the array of types
   --  in Columns_Types.

   Icon_Column               : constant := 0;
   Base_Name_Column          : constant := 1;
   Absolute_Name_Column      : constant := 2;   --  Get_File
   Mark_Column               : constant := 3;
   Line_Column               : constant := 4;
   Column_Column             : constant := 5;
   Length_Column             : constant := 6;
   Color_Column              : constant := 7;
   Button_Column             : constant := 8;
   Action_Column             : constant := 9;
   Highlight_Column          : constant := 10;
   Highlight_Category_Column : constant := 11;  --  Get_Highlighting_Style
   Number_Of_Items_Column    : constant := 12;
   Category_Line_Column      : constant := 13;

   function Get_File
     (Model : not null access Gtk.Tree_Model.Gtk_Tree_Model_Record'Class;
      Iter  : Gtk.Tree_Model.Gtk_Tree_Iter) return GNATCOLL.VFS.Virtual_File;
   --  Return the file stored at Iter

   function Get_Highlighting_Style
     (Model : not null access Gtk.Tree_Model.Gtk_Tree_Model_Record'Class;
      Iter  : Gtk.Tree_Model.Gtk_Tree_Iter)
      return GPS.Kernel.Styles.Style_Access;
   --  Return the highlighting style stored at Iter

   function Get_Category_Name
     (Model    : access Gtk_Tree_Model_Record'Class;
      Category : Gtk_Tree_Iter) return String;
   --  Return the name of the category associated with that iterator

   procedure Get_Category_File
     (Model           : Gtk_Tree_Store;
      Category        : Glib.UTF8_String;
      File            : GNATCOLL.VFS.Virtual_File;
      Category_Iter   : out Gtk_Tree_Iter;
      File_Iter       : out Gtk_Tree_Iter;
      New_Category    : out Boolean;
      Create          : Boolean;
      Category_Pixbuf : Gdk.Pixbuf.Gdk_Pixbuf := Null_Pixbuf;
      File_Pixbuf     : Gdk.Pixbuf.Gdk_Pixbuf := Null_Pixbuf;
      Color           : access Gdk.Color.Gdk_Color := null);
   --  Return the iter corresponding to Category, create it if
   --  necessary and if Create is True.
   --  If File is "", then the category iter will be returned.
   --  If the category was created, New_Category is set to True.
   --  Category is the escaped string.

   function Get_Message
     (Model : not null access Gtk_Tree_Model_Record'Class;
      Iter  : Gtk_Tree_Iter) return String;
   --  Return the message stored at Iter

   procedure Get_Line_Column_Iter
     (Model     : not null access Gtk_Tree_Model_Record'Class;
      File_Iter : Gtk_Tree_Iter;
      Line      : Natural;
      Column    : Natural := 0;
      Loc_Iter  : out Gtk_Tree_Iter);
   --  Get the iter corresponding to a line/column location within the file.
   --  If Column is not specified, only the line has to match.

   procedure Remove_Category
     (Kernel     : not null access Kernel_Handle_Record'Class;
      Model      : Gtk_Tree_Store;
      Identifier : String;
      File       : GNATCOLL.VFS.Virtual_File;
      Line       : Natural := 0);
   --  Remove category Identifier from the view. All corresponding marks
   --  are deleted.
   --  Identifier is the escaped string.

   procedure Fill_Iter
     (Model              : Gtk_Tree_Store;
      Iter               : Gtk_Tree_Iter;
      Base_Name          : String;
      Absolute_Name      : GNATCOLL.VFS.Virtual_File;
      Message            : Glib.UTF8_String;
      Mark               : Editor_Mark'Class := Nil_Editor_Mark;
      Line               : Integer;
      Column             : Visible_Column_Type;
      Length             : Integer;
      Highlighting       : Boolean;
      Highlight_Category : Style_Access;
      Pixbuf             : Gdk.Pixbuf.Gdk_Pixbuf := Null_Pixbuf;
      Color              : access Gdk.Color.Gdk_Color := null);
   --  Fill information in Iter.
   --  Base_Name can be left to the empty string, it will then be computed
   --  automatically from Absolute_Name.
   --  If Line is 0, consider the item as a non-leaf item.

   procedure Remove_Category_Or_File_Iter
     (Kernel : not null access Kernel_Handle_Record'Class;
      Model  : Gtk_Tree_Store;
      Iter   : in out Gtk_Tree_Iter;
      Line   : Natural := 0);
   --  Clear all the marks and highlightings in file or category
   --  ??? Document parameter Line.

   procedure Recount_Category
     (Model    : Gtk_Tree_Store;
      Category : String);
   --  Update the counters for Category

   function Columns_Types return Glib.GType_Array;
   --  Returns the types for the columns in the Model.
   --  This is not implemented as
   --       Columns_Types : constant GType_Array ...
   --  because Gdk.Pixbuf.Get_Type cannot be called before
   --  Gtk.Main.Init.

   Items_Count_Matcher : constant Pattern_Matcher :=
                           Compile ("( \([0-9]+ item[s]?\))$");

end GPS.Location_Model;
