-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2001-2003                       --
--                            ACT-Europe                             --
--                                                                   --
-- GPS is free  software; you can  redistribute it and/or modify  it --
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

with Glib;                     use Glib;
with Glib.Object;              use Glib.Object;
with Glib.Properties;          use Glib.Properties;
with Glib.Properties.Creation; use Glib.Properties.Creation;
with Glib.XML;
with Gdk.Color;                use Gdk.Color;
with Gdk.Font;                 use Gdk.Font;
with Gdk.Keyval;               use Gdk.Keyval;
with Gdk.Types;                use Gdk.Types;
with Gtk.Adjustment;           use Gtk.Adjustment;
with Gtk.Box;                  use Gtk.Box;
with Gtk.Button;               use Gtk.Button;
with Gtk.Cell_Renderer_Text;   use Gtk.Cell_Renderer_Text;
with Gtk.Check_Button;         use Gtk.Check_Button;
with Gtk.Combo;                use Gtk.Combo;
with Gtk.Dialog;               use Gtk.Dialog;
with Gtk.Enums;                use Gtk.Enums;
with Gtk.Event_Box;            use Gtk.Event_Box;
with Gtk.Font_Selection;       use Gtk.Font_Selection;
with Gtk.Frame;                use Gtk.Frame;
with Gtk.GEntry;               use Gtk.GEntry;
with Gtk.Handlers;             use Gtk.Handlers;
with Gtk.Label;                use Gtk.Label;
with Gtk.List;                 use Gtk.List;
with Gtk.List_Item;            use Gtk.List_Item;
with Gtk.Scrolled_Window;      use Gtk.Scrolled_Window;
with Gtk.Separator;            use Gtk.Separator;
with Gtk.Spin_Button;          use Gtk.Spin_Button;
with Gtk.Stock;                use Gtk.Stock;
with Gtk.Style;                use Gtk.Style;
with Gtk.Table;                use Gtk.Table;
with Gtk.Tree_View;            use Gtk.Tree_View;
with Gtk.Tree_View_Column;     use Gtk.Tree_View_Column;
with Gtk.Tree_Selection;       use Gtk.Tree_Selection;
with Gtk.Tree_Store;           use Gtk.Tree_Store;
with Gtk.Tree_Model;           use Gtk.Tree_Model;
with Gtk.Toggle_Button;        use Gtk.Toggle_Button;
with Gtk.Tooltips;             use Gtk.Tooltips;
with Gtk.Widget;               use Gtk.Widget;
with Gtk.Window;               use Gtk.Window;
with Gtkada.Handlers;          use Gtkada.Handlers;
with GVD.Color_Combo;          use GVD.Color_Combo;
with Pango.Font;               use Pango.Font;
with Basic_Types;              use Basic_Types;
with GNAT.OS_Lib;              use GNAT.OS_Lib;
with Unchecked_Deallocation;
with String_Utils;             use String_Utils;
with GUI_Utils;                use GUI_Utils;
with Odd_Intl;                 use Odd_Intl;
with Pango.Layout;             use Pango.Layout;

package body Default_Preferences is

   Fallback_Font : constant String := "Sans 10";
   --  The name of a font that should always work on all systems. This is used
   --  in case the user-specified fonts can not be found.

   use XML_Font;

   procedure Free is new Unchecked_Deallocation
     (Preference_Information, Preference_Information_Access);

   type Nodes is record
      Top     : Node_Ptr;
      Param   : Param_Spec;
   end record;
   package Param_Handlers is new Gtk.Handlers.User_Callback
     (Glib.Object.GObject_Record, Nodes);
   package Return_Param_Handlers is new Gtk.Handlers.User_Return_Callback
     (Glib.Object.GObject_Record, Boolean, Nodes);

   procedure Destroy_Cache (Data : in out XML_Cache);
   --  Free the memory occupied by Data

   function Find_Node_By_Name
     (Preferences : Node_Ptr; Name : String) return Node_Ptr;
   pragma Inline (Find_Node_By_Name);

   function Find_Node_By_Spec
     (Manager : access Preferences_Manager_Record'Class; Param : Param_Spec)
      return Node_Ptr;
   pragma Inline (Find_Node_By_Spec);
   --  Return the node from the XML tree that matches Param.

   function Find_Default_By_Param
     (Manager : access Preferences_Manager_Record'Class; Param : Param_Spec)
      return Preference_Information_Access;
   pragma Inline (Find_Default_By_Param);
   --  Return the information for the preference Name.

   generic
      type Param is private;
      P : Param_Spec;
      type Result (<>) is private;
      Val_Type : GType;
      with function Convert (S : String) return Result;
      with function Default (P : Param) return Result is <>;
   function Generic_Get_Pref
     (Manager : access Preferences_Manager_Record'Class; Pref : Param)
      return Result;
   --  ???

   procedure Toggled_Boolean (Toggle : access Gtk_Widget_Record'Class);
   --  Called when a toggle button has changed, to display the appropriate text
   --  in it.

   procedure Enum_Changed
     (Combo : access GObject_Record'Class;
      Data  : Nodes);
   --  Called when an enumeration preference has been changed.

   procedure Gint_Changed
     (Adj  : access GObject_Record'Class;
      Data : Nodes);
   --  Called when a Gint preference has been changed.

   procedure Boolean_Changed
     (Toggle : access GObject_Record'Class;
      Data   : Nodes);
   --  Called when a boolean preference has been changed.

   procedure Entry_Changed
     (Ent  : access GObject_Record'Class;
      Data : Nodes);
   --  Called when the text in an entry field has changed.

   function Font_Entry_Changed
     (Ent  : access GObject_Record'Class;
      Data : Nodes) return Boolean;
   --  Called when the entry for a font selection has changed.

   procedure Reset_Font (Ent : access Gtk_Widget_Record'Class);
   --  Update the font used for the entry Ent, based on its contents.

   procedure Color_Changed
     (Combo : access GObject_Record'Class;
      Data  : Nodes);
   --  Called when a color has changed.

   procedure Bg_Color_Changed
     (Combo : access GObject_Record'Class; Data  : Nodes);
   --  Called when the background color of a style has changed.

   procedure Fg_Color_Changed
     (Combo : access GObject_Record'Class; Data  : Nodes);
   --  Called when the foreground color of a style has changed.

   function Value (S : String) return String;
   --  Return the string as is (used for instantiation of Generic_Get_Pref)

   procedure Set_Pref (Top : Node_Ptr; Name : String; Value : String);
   --  Set or create preference.

   procedure Select_Font
     (Ent : access GObject_Record'Class; Data : Nodes);
   --  Open a dialog to select a new font

   procedure Reset_Specific_Data (Node : Node_Ptr);
   --  Remove (but do not free), the cached data associated with each node.

   procedure Key_Grab (Ent  : access Gtk_Widget_Record'Class);
   --  Callback for the "grab" button when editing a key preference

   function To_String (Font, Fg, Bg : String) return String;
   function Style_Token (Value : String; Num : Positive) return String;
   --  Handling of Param_Spec_Style

   procedure Get_Font
     (Manager : access Preferences_Manager_Record'Class;
      Pref    : Param_Spec;
      N       : in out Node_Ptr;
      Desc    : in out Pango_Font_Description);
   --  Check that Desc is a valid font, and associate it with the node N.

   function Create_Box_For_Font
     (N            : Nodes;
      Desc         : Pango_Font_Description;
      Button_Label : String) return Gtk_Box;
   --  Create a box suitable for editing fonts

   -------------------
   -- Destroy_Cache --
   -------------------

   procedure Destroy_Cache (Data : in out XML_Cache) is
   begin
      if Data.Descr /= null then
         Free (Data.Descr);
         Data.Descr := null;
      end if;
   end Destroy_Cache;

   -----------
   -- Value --
   -----------

   function Value (S : String) return String is
   begin
      return S;
   end Value;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Manager : in out Preferences_Manager_Record) is
      N : Preference_Information_Access;
   begin
      while Manager.Default /= null loop
         N := Manager.Default.Next;
         Free (Manager.Default.Page);
         Unref (Manager.Default.Param);
         Free (Manager.Default);
         Manager.Default := N;
      end loop;

      Free (Manager.Preferences, Destroy_Cache'Access);
   end Destroy;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Manager : in out Preferences_Manager) is
      procedure Unchecked_Free is new Unchecked_Deallocation
        (Preferences_Manager_Record'Class, Preferences_Manager);
   begin
      Destroy (Manager.all);
      Unchecked_Free (Manager);
   end Destroy;

   ----------------
   -- Gnew_Color --
   ----------------

   function Gnew_Color
     (Name, Nick, Blurb : String;
      Default           : String;
      Flags             : Param_Flags := Param_Readable or Param_Writable)
      return Param_Spec_Color
   is
      P : constant Param_Spec_Color := Param_Spec_Color
        (Gnew_String (Name, Nick, Blurb, Default, Flags));
   begin
      Set_Value_Type (Param_Spec (P), Gdk.Color.Gdk_Color_Type);
      return P;
   end Gnew_Color;

   ---------------
   -- Gnew_Font --
   ---------------

   function Gnew_Font
     (Name, Nick, Blurb : String;
      Default           : String;
      Flags             : Param_Flags := Param_Readable or Param_Writable)
      return Param_Spec_Font
   is
      P : constant Param_Spec_Font := Param_Spec_Font
        (Gnew_String (Name, Nick, Blurb, Default, Flags));
   begin
      Set_Value_Type (Param_Spec (P), Pango.Font.Get_Type);
      return P;
   end Gnew_Font;

   --------------
   -- Gnew_Key --
   --------------

   function Gnew_Key
     (Name, Nick, Blurb : String;
      Default_Modifier  : Gdk.Types.Gdk_Modifier_Type;
      Default_Key       : Gdk.Types.Gdk_Key_Type;
      Flags             : Param_Flags := Param_Readable or Param_Writable)
      return Param_Spec_Key
   is
      P : constant Param_Spec_Key := Param_Spec_Key
        (Gnew_String (Name, Nick, Blurb,
                      Image (Default_Key, Default_Modifier),
                      Flags));
   begin
      Set_Value_Type (Param_Spec (P), Gdk.Keyval.Get_Type);
      return P;
   end Gnew_Key;

   ----------------
   -- Gnew_Style --
   ----------------

   function Gnew_Style
     (Name, Nick, Blurb : String;
      Default_Font      : String;
      Default_Fg        : String;
      Default_Bg        : String;
      Flags             : Param_Flags := Param_Readable or Param_Writable)
      return Param_Spec_Style
   is
      P : constant Param_Spec_Style := Param_Spec_Style
        (Gnew_String (Name, Nick, Blurb,
                      To_String (Default_Font, Default_Fg, Default_Bg),
                      Flags));
   begin
      Set_Value_Type (Param_Spec (P), Gtk.Style.Get_Type);
      return P;
   end Gnew_Style;

   -----------------------
   -- Register_Property --
   -----------------------

   procedure Register_Property
     (Manager : access Preferences_Manager_Record;
      Param   : Glib.Param_Spec;
      Page    : String)
   is
      N : Preference_Information_Access := Manager.Default;
      Prev : Preference_Information_Access := null;
   begin
      while N /= null loop
         if N.Param = Param then
            Free (N.Page);
            N.Page := new String'(Page);
            return;
         end if;
         Prev := N;
         N := N.Next;
      end loop;

      if Prev /= null then
         Prev.Next := new Preference_Information'
           (Page  => new String'(Page),
            Param => Param,
            Next  => null);
      else
         Manager.Default := new Preference_Information'
           (Page  => new String'(Page),
            Param => Param,
            Next  => null);
      end if;
   end Register_Property;

   -----------------------
   -- Find_Node_By_Spec --
   -----------------------

   function Find_Node_By_Spec
     (Manager : access Preferences_Manager_Record'Class;
      Param : Param_Spec) return Node_Ptr is
   begin
      return Find_Node_By_Name (Manager.Preferences, Pspec_Name (Param));
   end Find_Node_By_Spec;

   -----------------------
   -- Find_Node_By_Name --
   -----------------------

   function Find_Node_By_Name
     (Preferences : Node_Ptr; Name : String) return Node_Ptr
   is
      N : Node_Ptr;
   begin
      if Preferences /= null then
         N := Find_Tag (Preferences.Child, Name);
      end if;

      return N;
   end Find_Node_By_Name;

   ---------------------------
   -- Find_Default_By_Param --
   ---------------------------

   function Find_Default_By_Param
     (Manager : access Preferences_Manager_Record'Class; Param : Param_Spec)
      return Preference_Information_Access
   is
      N : Preference_Information_Access := Manager.Default;
   begin
      while N /= null and then N.Param /= Param loop
         N := N.Next;
      end loop;
      return N;
   end Find_Default_By_Param;

   ----------------------
   -- Generic_Get_Pref --
   ----------------------

   function Generic_Get_Pref
     (Manager : access Preferences_Manager_Record'Class; Pref : Param)
      return Result
   is
      N : constant Node_Ptr := Find_Node_By_Spec (Manager, P);
   begin
      if N /= null
        and then (Value_Type (P) = Val_Type
                  or else Fundamental (Value_Type (P)) = Val_Type)
        and then N.Value.all /= ""
      then
         return Convert (N.Value.all);
      end if;

      return Default (Pref);

   exception
      when Constraint_Error =>
         return Default (Pref);
   end Generic_Get_Pref;

   --------------
   -- Get_Pref --
   --------------

   function Get_Pref
     (Manager : access Preferences_Manager_Record; Pref : Param_Spec_Int)
      return Gint
   is
      function Internal is new Generic_Get_Pref
        (Param_Spec_Int, Param_Spec (Pref), Gint, GType_Int, Gint'Value);
   begin
      return Internal (Manager, Pref);
   end Get_Pref;

   --------------
   -- Get_Pref --
   --------------

   function Get_Pref
     (Manager : access Preferences_Manager_Record; Pref : Param_Spec_Boolean)
      return Boolean
   is
      function Internal is new Generic_Get_Pref
        (Param_Spec_Boolean, Param_Spec (Pref), Boolean, GType_Boolean,
         Boolean'Value);
   begin
      return Internal (Manager, Pref);
   end Get_Pref;

   --------------
   -- Get_Pref --
   --------------

   function Get_Pref
     (Manager : access Preferences_Manager_Record; Pref : Param_Spec_Enum)
      return Gint
   is
      function Internal is new Generic_Get_Pref
        (Param_Spec_Enum, Param_Spec (Pref), Gint, GType_Enum, Gint'Value);
   begin
      return Internal (Manager, Pref);
   end Get_Pref;

   --------------
   -- Get_Pref --
   --------------

   function Get_Pref
     (Manager : access Preferences_Manager_Record; Pref : Param_Spec_String)
      return String
   is
      function Internal is new Generic_Get_Pref
        (Param_Spec_String, Param_Spec (Pref), String, GType_String, Value);
   begin
      return Internal (Manager, Pref);
   end Get_Pref;

   --------------
   -- Get_Pref --
   --------------

   function Get_Pref
     (Manager : access Preferences_Manager_Record;
      Pref   : Param_Spec_Color) return Gdk.Color.Gdk_Color
   is
      function Internal is new Generic_Get_Pref
        (Param_Spec_Color, Param_Spec (Pref), String, Gdk_Color_Type, Value);
      S : constant String := Internal (Manager, Pref);
      Color : Gdk_Color;
   begin
      Color := Parse (S);
      Alloc (Gtk.Widget.Get_Default_Colormap, Color);
      return Color;

   exception
      when Wrong_Color =>
         Color := Black (Get_Default_Colormap);
         return Color;
   end Get_Pref;

   --------------
   -- Get_Pref --
   --------------

   procedure Get_Pref
     (Manager  : access Preferences_Manager_Record;
      Pref     : Param_Spec_Key;
      Modifier : out Gdk_Modifier_Type;
      Key      : out Gdk_Key_Type)
   is
      N : constant Node_Ptr := Find_Node_By_Spec (Manager, Param_Spec (Pref));
   begin
      if N /= null
        and then N.Value.all /= ""
      then
         Value (N.Value.all, Key, Modifier);
         return;
      end if;

      Value (Default (Param_Spec_String (Pref)), Key, Modifier);
   end Get_Pref;

   -------------------
   -- Get_Pref_Font --
   -------------------

   function Get_Pref_Font
     (Manager  : access Preferences_Manager_Record;
      Pref     : Param_Spec_Style) return Pango_Font_Description
   is
      N    : Node_Ptr := Find_Node_By_Spec (Manager, Param_Spec (Pref));
      Desc : Pango_Font_Description;
   begin
      if N /= null and then N.Value.all /= "" then
         if N.Specific_Data.Descr /= null then
            return N.Specific_Data.Descr;
         end if;

         Desc := From_String (Style_Token (N.Value.all, 1));
      else
         Desc := From_String
           (Style_Token (Default (Param_Spec_String (Pref)), 1));
      end if;

      Get_Font (Manager, Param_Spec (Pref), N, Desc);
      return Desc;
   end Get_Pref_Font;

   --------------
   -- Get_Font --
   --------------

   procedure Get_Font
     (Manager : access Preferences_Manager_Record'Class;
      Pref    : Param_Spec;
      N       : in out Node_Ptr;
      Desc    : in out Pango_Font_Description)
   is
      use type Gdk.Gdk_Font;
   begin
      --  Check that the font exists, or use a default, to avoid crashes
      if From_Description (Desc) = null then
         Free (Desc);
         Desc := From_String (Fallback_Font);
      end if;

      --  We must have a node to store the cached font description and avoid
      --  memory leaks.
      if N = null then
         if Value_Type (Pref) = Pango.Font.Get_Type then
            Set_Pref (Manager, Pspec_Name (Pref), To_String (Desc));
         else
            Set_Pref
              (Manager, Pspec_Name (Pref),
               To_String
               (Font => To_String (Desc),
                Fg   => Style_Token (Default (Param_Spec_String (Pref)), 2),
                Bg   => Style_Token (Default (Param_Spec_String (Pref)), 3)));
         end if;
         N := Find_Node_By_Spec (Manager, Pref);
      end if;

      N.Specific_Data.Descr := Desc;
   end Get_Font;

   -----------------
   -- Get_Pref_Fg --
   -----------------

   function Get_Pref_Fg
     (Manager  : access Preferences_Manager_Record;
      Pref     : Param_Spec_Style) return Gdk.Color.Gdk_Color
   is
      N : Node_Ptr := Find_Node_By_Spec (Manager, Param_Spec (Pref));
      Color : Gdk_Color;
   begin
      if N = null then
         Set_Pref
           (Manager, Pspec_Name (Param_Spec (Pref)),
            Default (Param_Spec_String (Pref)));
         N := Find_Node_By_Spec (Manager, Param_Spec (Pref));
      end if;

      Color := Parse (Style_Token (N.Value.all, 2));
      Alloc (Gtk.Widget.Get_Default_Colormap, Color);
      return Color;
   end Get_Pref_Fg;

   -----------------
   -- Get_Pref_Bg --
   -----------------

   function Get_Pref_Bg
     (Manager  : access Preferences_Manager_Record;
      Pref     : Param_Spec_Style) return Gdk.Color.Gdk_Color
   is
      N : Node_Ptr := Find_Node_By_Spec (Manager, Param_Spec (Pref));
      Color : Gdk_Color;
   begin
      if N = null then
         Set_Pref
           (Manager, Pspec_Name (Param_Spec (Pref)),
            Default (Param_Spec_String (Pref)));
         N := Find_Node_By_Spec (Manager, Param_Spec (Pref));
      end if;

      Color := Parse (Style_Token (N.Value.all, 3));
      Alloc (Gtk.Widget.Get_Default_Colormap, Color);
      return Color;
   end Get_Pref_Bg;

   --------------
   -- Get_Pref --
   --------------

   function Get_Pref
     (Manager : access Preferences_Manager_Record;
      Pref    : Param_Spec_Font) return Pango.Font.Pango_Font_Description
   is
      N : Node_Ptr := Find_Node_By_Spec (Manager, Param_Spec (Pref));
      Desc : Pango_Font_Description;
   begin
      if N /= null
        and then N.Value.all /= ""
      then
         if N.Specific_Data.Descr /= null then
            return N.Specific_Data.Descr;
         else
            Desc := From_String (N.Value.all);
         end if;
      else
         Desc := From_String (Default (Pref));
      end if;

      Get_Font (Manager, Param_Spec (Pref), N, Desc);
      return Desc;
   end Get_Pref;

   --------------
   -- Set_Pref --
   --------------

   procedure Set_Pref (Top : Node_Ptr; Name : String; Value : String) is
      N : Node_Ptr := Find_Node_By_Name (Top, Name);
   begin
      if N = null then
         N     := new XML_Font.Node;
         N.Tag := new String'(Name);
         Add_Child (Top, N);
      else
         Destroy_Cache (N.Specific_Data);
         XML_Font.Free (N.Value);
      end if;

      N.Value := new String'(Value);
   end Set_Pref;

   --------------
   -- Set_Pref --
   --------------

   procedure Set_Pref
     (Manager : access Preferences_Manager_Record;
      Name : String; Value : String) is
   begin
      Set_Pref (Manager.Preferences, Name, Value);
   end Set_Pref;

   --------------
   -- Set_Pref --
   --------------

   procedure Set_Pref
     (Manager : access Preferences_Manager_Record;
      Name : String; Value : Gint) is
   begin
      Set_Pref (Manager.Preferences, Name, Gint'Image (Value));
   end Set_Pref;

   --------------
   -- Set_Pref --
   --------------

   procedure Set_Pref
     (Manager  : access Preferences_Manager_Record;
      Name     : String;
      Modifier : Gdk_Modifier_Type;
      Key      : Gdk_Key_Type) is
   begin
      Set_Pref (Manager.Preferences, Name, Image (Key, Modifier));
   end Set_Pref;

   --------------
   -- Set_Pref --
   --------------

   procedure Set_Pref
     (Manager      : access Preferences_Manager_Record;
      Name         : String;
      Font, Fg, Bg : String) is
   begin
      Set_Pref (Manager.Preferences, Name, To_String (Font, Fg, Bg));
   end Set_Pref;

   --------------
   -- Set_Pref --
   --------------

   procedure Set_Pref
     (Manager : access Preferences_Manager_Record;
      Name : String; Value : Boolean) is
   begin
      Set_Pref (Manager.Preferences, Name, Boolean'Image (Value));
   end Set_Pref;

   --------------
   -- Get_Page --
   --------------

   function Get_Page
     (Manager : access Preferences_Manager_Record;
      Param : Param_Spec) return String is
   begin
      return Find_Default_By_Param (Manager, Param).Page.all;
   end Get_Page;

   ----------------------
   -- Load_Preferences --
   ----------------------

   procedure Load_Preferences
     (Manager : access  Preferences_Manager_Record; File_Name : String) is
   begin
      Free (Manager.Preferences, Destroy_Cache'Access);
      if Is_Regular_File (File_Name) then
         Manager.Preferences := Parse (File_Name);
      else
         Manager.Preferences := new XML_Font.Node;
         Manager.Preferences.Tag := new String'("Preferences");
      end if;
   end Load_Preferences;

   ----------------------
   -- Save_Preferences --
   ----------------------

   procedure Save_Preferences
     (Manager : access Preferences_Manager_Record; File_Name : String)
   is
      N  : Preference_Information_Access := Manager.Default;
      N2 : Node_Ptr;
   begin
      --  Create the tree if necessary
      if Manager.Preferences = null then
         Manager.Preferences := new Node;
         Manager.Preferences.Tag := new String'("Preferences");
      end if;

      --  Make sure that all the registered preferences also exist in the
      --  current preferences.
      --  This isn't required unless we want to create a manually editable
      --  preference file.
      while N /= null loop
         if Find_Node_By_Name (Manager.Preferences, Pspec_Name (N.Param))
           = null
         then
            N2 := new Node;
            N2.Tag := new String'(Pspec_Name (N.Param));

            if Value_Type (N.Param) = GType_Int then
               N2.Value := new String'
                 (Gint'Image (Default (Param_Spec_Int (N.Param))));

            elsif Value_Type (N.Param) = GType_Boolean then
               N2.Value := new String'
                 (Boolean'Image (Default (Param_Spec_Boolean (N.Param))));

            elsif Fundamental (Value_Type (N.Param)) = GType_Enum then
               N2.Value := new String'
                 (Gint'Image (Default (Param_Spec_Enum (N.Param))));

            else
               N2.Value := new String'
                 (Default (Param_Spec_String (N.Param)));
            end if;

            Add_Child (Manager.Preferences, N2);
         end if;
         N := N.Next;
      end loop;

      Print (Manager.Preferences, File_Name => File_Name);
   end Save_Preferences;

   ---------------------
   -- Toggled_Boolean --
   ---------------------

   procedure Toggled_Boolean (Toggle : access Gtk_Widget_Record'Class) is
      T : constant Gtk_Toggle_Button := Gtk_Toggle_Button (Toggle);
   begin
      if Get_Active (T) then
         Set_Text (Gtk_Label (Get_Child (T)), -"(Enabled)");
      else
         Set_Text (Gtk_Label (Get_Child (T)), -"(Disabled)");
      end if;
   end Toggled_Boolean;

   ------------------
   -- Enum_Changed --
   ------------------

   procedure Enum_Changed
     (Combo : access GObject_Record'Class;
      Data  : Nodes)
   is
      C : constant Gtk_Combo := Gtk_Combo (Combo);
   begin
      Set_Pref (Data.Top, Pspec_Name (Data.Param),
                Integer'Image (Get_Index_In_List (C)));
   end Enum_Changed;

   ------------------
   -- Gint_Changed --
   ------------------

   procedure Gint_Changed
     (Adj  : access GObject_Record'Class;
      Data : Nodes)
   is
      A : constant Gtk_Adjustment := Gtk_Adjustment (Adj);
   begin
      Set_Pref (Data.Top, Pspec_Name (Data.Param),
                Gint'Image (Gint (Get_Value (A))));
   end Gint_Changed;

   ---------------------
   -- Boolean_Changed --
   ---------------------

   procedure Boolean_Changed
     (Toggle : access GObject_Record'Class;
      Data   : Nodes)
   is
      T : constant Gtk_Toggle_Button := Gtk_Toggle_Button (Toggle);
   begin
      Set_Pref (Data.Top, Pspec_Name (Data.Param),
                Boolean'Image (Get_Active (T)));
   end Boolean_Changed;

   -------------------
   -- Entry_Changed --
   -------------------

   procedure Entry_Changed
     (Ent  : access GObject_Record'Class;
      Data : Nodes)
   is
      E : constant Gtk_Entry := Gtk_Entry (Ent);
   begin
      Set_Pref (Data.Top, Pspec_Name (Data.Param), Get_Text (E));
   end Entry_Changed;

   ----------------
   -- Reset_Font --
   ----------------

   procedure Reset_Font (Ent : access Gtk_Widget_Record'Class) is
      E    : constant Gtk_Entry := Gtk_Entry (Ent);
      Desc : constant Pango_Font_Description := From_String (Get_Text (E));
   begin
      --  Also set the context, so that every time the pango layout is
      --  recreated by the entry (key press,...), we still use the correct
      --  font.
      --  ??? Right now, the mechanism described above will cause gtk to
      --  crash when Desc doesn't correspond to a drawable font, therefore
      --  the following code is commented out.
      --  Set_Font_Description (Get_Pango_Context (E), Desc);

      Set_Font_Description (Get_Layout (E), Desc);
   end Reset_Font;

   ------------------------
   -- Font_Entry_Changed --
   ------------------------

   function Font_Entry_Changed
     (Ent  : access GObject_Record'Class;
      Data : Nodes) return Boolean
   is
      E : constant Gtk_Entry := Gtk_Entry (Ent);
      N      : Node_Ptr;
   begin
      if Value_Type (Data.Param) = Pango.Font.Get_Type then
         Set_Pref (Data.Top, Pspec_Name (Data.Param), Get_Text (E));
      else
         N := Find_Node_By_Name (Data.Top, Pspec_Name (Data.Param));

         if N.Value /= null then
            Set_Pref
              (Data.Top, Pspec_Name (Data.Param),
               To_String (Font => Get_Text (E),
                          Fg   => Style_Token (N.Value.all, 2),
                          Bg   => Style_Token (N.Value.all, 3)));
         else
            Set_Pref
              (Data.Top, Pspec_Name (Data.Param),
               To_String (Font => Get_Text (E),
                          Fg   => Style_Token
                          (Default (Param_Spec_String (Data.Param)), 2),
                          Bg   => Style_Token
                          (Default (Param_Spec_String (Data.Param)), 3)));
         end if;
      end if;

      Reset_Font (E);
      return False;
   end Font_Entry_Changed;

   --------------
   -- Key_Grab --
   --------------

   procedure Key_Grab (Ent : access Gtk_Widget_Record'Class) is
      E      : constant Gtk_Entry := Gtk_Entry (Ent);
      Key    : Gdk.Types.Gdk_Key_Type;
      Mods   : Gdk.Types.Gdk_Modifier_Type;
   begin
      GUI_Utils.Key_Grab (E, Key, Mods);
      Set_Text (E, Image (Key, Mods));
   end Key_Grab;

   -------------------
   -- Color_Changed --
   -------------------

   procedure Color_Changed
     (Combo : access GObject_Record'Class;
      Data  : Nodes)
   is
      C : constant Gvd_Color_Combo := Gvd_Color_Combo (Combo);
   begin
      Set_Pref (Data.Top, Pspec_Name (Data.Param), Get_Color (C));
   end Color_Changed;

   ----------------------
   -- Fg_Color_Changed --
   ----------------------

   procedure Fg_Color_Changed
     (Combo : access GObject_Record'Class;
      Data  : Nodes)
   is
      C : constant Gvd_Color_Combo := Gvd_Color_Combo (Combo);
      N : constant Node_Ptr := Find_Node_By_Name
        (Data.Top, Pspec_Name (Data.Param));
   begin
      if N.Value = null then
         declare
            V : constant String := Default (Param_Spec_String (Data.Param));
         begin
            Set_Pref (Data.Top, Pspec_Name (Data.Param),
                      To_String (Font => Style_Token (V, 1),
                                 Fg   => Get_Color (C),
                                 Bg   => Style_Token (V, 3)));
         end;

      else
         Set_Pref (Data.Top, Pspec_Name (Data.Param),
                   To_String (Font => Style_Token (N.Value.all, 1),
                              Fg   => Get_Color (C),
                              Bg   => Style_Token (N.Value.all, 3)));
      end if;
   end Fg_Color_Changed;

   ----------------------
   -- Bg_Color_Changed --
   ----------------------

   procedure Bg_Color_Changed
     (Combo : access GObject_Record'Class;
      Data  : Nodes)
   is
      C : constant Gvd_Color_Combo := Gvd_Color_Combo (Combo);
      N : constant Node_Ptr := Find_Node_By_Name
        (Data.Top, Pspec_Name (Data.Param));
   begin
      if N.Value = null then
         declare
            V : constant String := Default (Param_Spec_String (Data.Param));
         begin
            Set_Pref (Data.Top, Pspec_Name (Data.Param),
                      To_String (Font => Style_Token (V, 1),
                                 Fg   => Style_Token (V, 2),
                                 Bg   => Get_Color (C)));
         end;

      else
         Set_Pref (Data.Top, Pspec_Name (Data.Param),
                   To_String (Font => Style_Token (N.Value.all, 1),
                              Fg   => Style_Token (N.Value.all, 2),
                              Bg   => Get_Color (C)));
      end if;
   end Bg_Color_Changed;

   ---------------
   -- To_String --
   ---------------

   function To_String (Font, Fg, Bg : String) return String is
   begin
      return Font & '@' & Fg & '@' & Bg;
   end To_String;

   -----------------
   -- Style_Token --
   -----------------

   function Style_Token (Value : String; Num : Positive) return String is
      Start, Last : Natural := Value'First;
      N : Natural := Num;
   begin
      loop
         if Last > Value'Last then
            return Value (Start .. Last - 1);

         elsif Value (Last) = '@' then
            N := N - 1;
            if N = 0 then
               return Value (Start .. Last - 1);
            end if;

            Start := Last + 1;
         end if;

         Last := Last + 1;
      end loop;

      return "";
   end Style_Token;

   -----------------
   -- Select_Font --
   -----------------

   procedure Select_Font
     (Ent : access GObject_Record'Class;
      Data : Nodes)
   is
      E      : constant Gtk_Entry := Gtk_Entry (Ent);
      F      : Gtk_Font_Selection;
      Dialog : Gtk_Dialog;
      Result : Boolean;
      Tmp    : Gtk_Widget;
      pragma Unreferenced (Result, Tmp);
      N      : Node_Ptr;

   begin
      Gtk_New (Dialog,
               Title  => -"Select font",
               Parent => Gtk_Window (Get_Toplevel (E)),
               Flags  => Modal or Destroy_With_Parent);

      Gtk_New (F);
      Result := Set_Font_Name (F, Get_Text (E));
      Pack_Start (Get_Vbox (Dialog), F, Expand => True, Fill => True);

      Tmp := Add_Button (Dialog, Stock_Ok,     Gtk_Response_OK);
      Tmp := Add_Button (Dialog, Stock_Cancel, Gtk_Response_Cancel);

      Show_All (Dialog);

      if Run (Dialog) = Gtk_Response_OK then
         Set_Text (E, Get_Font_Name (F));

         if Value_Type (Data.Param) = Pango.Font.Get_Type then
            Set_Pref (Data.Top, Pspec_Name (Data.Param), Get_Text (E));
         else
            N := Find_Node_By_Name (Data.Top, Pspec_Name (Data.Param));

            if N.Value /= null then
               Set_Pref
                 (Data.Top, Pspec_Name (Data.Param),
                  To_String (Font => Get_Text (E),
                             Fg   => Style_Token (N.Value.all, 2),
                             Bg   => Style_Token (N.Value.all, 3)));
            else
               Set_Pref
                 (Data.Top, Pspec_Name (Data.Param),
                  To_String (Font => Get_Text (E),
                             Fg   => Style_Token
                               (Default (Param_Spec_String (Data.Param)), 2),
                             Bg   => Style_Token
                               (Default (Param_Spec_String (Data.Param)), 3)));
            end if;
         end if;
         Reset_Font (E);
      end if;

      Destroy (Dialog);
   end Select_Font;

   -------------------------
   -- Create_Box_For_Font --
   -------------------------

   function Create_Box_For_Font
     (N            : Nodes;
      Desc         : Pango_Font_Description;
      Button_Label : String) return Gtk_Box
   is
      Box : Gtk_Box;
      Ent : Gtk_Entry;
      Button : Gtk_Button;
   begin
      Gtk_New_Hbox (Box, Homogeneous => False);
      Gtk_New (Ent);
      Pack_Start (Box, Ent, Expand => True, Fill => True);

      Gtk_New (Button, Button_Label);
      Pack_Start (Box, Button, Expand => False, Fill => False);
      Param_Handlers.Object_Connect
        (Button, "clicked",
         Param_Handlers.To_Marshaller (Select_Font'Access),
         Slot_Object => Ent,
         User_Data => N);

      Return_Param_Handlers.Connect
        (Ent, "focus_out_event",
         Return_Param_Handlers.To_Marshaller (Font_Entry_Changed'Access),
         User_Data   => N);

      Set_Style (Ent, Copy (Get_Style (Ent)));
      Set_Font_Description (Get_Style (Ent), Desc);
      Set_Text (Ent, To_String (Desc));
      Reset_Font (Ent);
      return Box;
   end Create_Box_For_Font;

   -------------------
   -- Editor_Widget --
   -------------------

   function Editor_Widget
     (Manager : access Preferences_Manager_Record;
      Param   : Param_Spec;
      Tips    : Gtk_Tooltips) return Gtk.Widget.Gtk_Widget
   is
      Typ : constant GType := Value_Type (Param);
      N   : constant Nodes := (Manager.Preferences, Param);
   begin
      if Typ = GType_Int then
         declare
            Prop : constant Param_Spec_Int := Param_Spec_Int (Param);
            Spin   : Gtk_Spin_Button;
            Adj    : Gtk_Adjustment;
         begin
            Gtk_New (Adj,
                     Value => Gdouble (Get_Pref (Manager, Prop)),
                     Lower => Gdouble (Minimum (Prop)),
                     Upper => Gdouble (Maximum (Prop)),
                     Step_Increment => 1.0,
                     Page_Increment => 10.0,
                     Page_Size      => 10.0);
            Gtk_New (Spin, Adj, 1.0, The_Digits => 0);
            Set_Editable (Spin, True);

            Param_Handlers.Connect
              (Adj, "value_changed",
               Param_Handlers.To_Marshaller (Gint_Changed'Access),
               User_Data   => N);

            return Gtk_Widget (Spin);
         end;

      elsif Typ = GType_Boolean then
         declare
            Prop : constant Param_Spec_Boolean := Param_Spec_Boolean (Param);
            Toggle : Gtk_Check_Button;
         begin
            Gtk_New (Toggle, -"Enabled");
            Widget_Callback.Connect
              (Toggle, "toggled",
               Widget_Callback.To_Marshaller
               (Toggled_Boolean'Access));
            Set_Active (Toggle, True); --  Forces a toggle
            Set_Active (Toggle, Get_Pref (Manager, Prop));

            Param_Handlers.Connect
              (Toggle, "toggled",
               Param_Handlers.To_Marshaller (Boolean_Changed'Access),
               User_Data   => N);

            return Gtk_Widget (Toggle);
         end;

      elsif Typ = Gdk.Keyval.Get_Type then
         declare
            Prop : constant Param_Spec_Key := Param_Spec_Key (Param);
            Ent  : Gtk_Entry;
            Modif : Gdk_Modifier_Type;
            Key   : Gdk_Key_Type;
            Button : Gtk_Button;
            Box    : Gtk_Box;
         begin
            Gtk_New_Hbox (Box);
            Gtk_New (Ent);
            Set_Editable (Ent, False);
            Pack_Start (Box, Ent, Expand => True, Fill => True);

            Gtk_New (Button, -"Grab...");
            Pack_Start (Box, Button, Expand => False);

            Get_Pref (Manager, Prop, Modif, Key);

            Append_Text (Ent, Image (Key, Modif));

            Widget_Callback.Object_Connect
              (Button, "clicked",
               Widget_Callback.To_Marshaller (Key_Grab'Access),
               Slot_Object => Ent);
            Param_Handlers.Connect
              (Ent, "insert_text",
               Param_Handlers.To_Marshaller (Entry_Changed'Access),
               User_Data   => N,
               After       => True);

            return Gtk_Widget (Box);
         end;

      elsif Typ = GType_String then
         declare
            Prop : constant Param_Spec_String := Param_Spec_String (Param);
            Ent  : Gtk_Entry;
         begin
            Gtk_New (Ent);
            Set_Text (Ent, Get_Pref (Manager, Prop));

            Param_Handlers.Connect
              (Ent, "insert_text",
               Param_Handlers.To_Marshaller (Entry_Changed'Access),
               User_Data   => N,
               After       => True);
            Param_Handlers.Connect
              (Ent, "delete_text",
               Param_Handlers.To_Marshaller (Entry_Changed'Access),
               User_Data   => N,
               After       => True);

            return Gtk_Widget (Ent);
         end;

      elsif Typ = Gtk.Style.Get_Type then
         declare
            Prop  : constant Param_Spec_Style := Param_Spec_Style (Param);
            Event : Gtk_Event_Box;
            Box   : Gtk_Box;
            F     : constant Gtk_Box := Create_Box_For_Font
              (N, Get_Pref_Font (Manager, Prop), "...");
            Combo : Gvd_Color_Combo;

         begin
            Gtk_New (Event);
            Add (Event, F);
            Set_Tip
              (Tips, Event, -"Click on ... to display the font selector");
            Gtk_New_Hbox (Box, Homogeneous => False);
            Pack_Start (Box, Event, Expand => True, Fill => True);

            Gtk_New (Event);
            Gtk_New (Combo);
            Add (Event, Combo);
            Set_Tip (Tips, Event, -"Foreground color");
            Pack_Start (Box, Event, Expand => False);
            Set_Color (Combo, Get_Pref_Fg (Manager, Prop));
            Param_Handlers.Connect
              (Combo, "color_changed",
               Param_Handlers.To_Marshaller (Fg_Color_Changed'Access),
               User_Data   => N);

            Gtk_New (Event);
            Gtk_New (Combo);
            Add (Event, Combo);
            Set_Tip (Tips, Event, -"Background color");
            Pack_Start (Box, Event, Expand => False);
            Set_Color (Combo, Get_Pref_Bg (Manager, Prop));
            Param_Handlers.Connect
              (Combo, "color_changed",
               Param_Handlers.To_Marshaller (Bg_Color_Changed'Access),
               User_Data   => N);

            return Gtk_Widget (Box);
         end;


      elsif Typ = Gdk.Color.Gdk_Color_Type then
         declare
            Prop : constant Param_Spec_Color := Param_Spec_Color (Param);
            Combo : Gvd_Color_Combo;
         begin
            Gtk_New (Combo);
            Set_Color (Combo, Get_Pref (Manager, Prop));

            Param_Handlers.Connect
              (Combo, "color_changed",
               Param_Handlers.To_Marshaller (Color_Changed'Access),
               User_Data   => N);

            return Gtk_Widget (Combo);
         end;

      elsif Typ = Pango.Font.Get_Type then
         declare
            Prop : constant Param_Spec_Font := Param_Spec_Font (Param);
         begin
            return Gtk_Widget
              (Create_Box_For_Font (N, Get_Pref (Manager, Prop), -"Browse"));
         end;

      elsif Fundamental (Typ) = GType_Enum then
         declare
            Prop : constant Param_Spec_Enum := Param_Spec_Enum (Param);
            V : constant Gint := Get_Pref (Manager, Prop);
            Combo   : Gtk_Combo;
            E_Klass : constant Enum_Class := Enumeration (Prop);
            Val     : Enum_Value;
            K       : Guint := 0;
            Item    : Gtk_List_Item;
         begin
            Gtk_New (Combo);
            Set_Value_In_List (Combo, True, Ok_If_Empty => False);
            Set_Editable (Get_Entry (Combo), False);

            loop
               Val := Nth_Value (E_Klass, K);
               exit when Val = null;
               declare
                  S : String := Nick (Val);
               begin
                  Mixed_Case (S);
                  Gtk_New (Item, S);
               end;
               Add (Get_List (Combo), Item);
               if Value (Val) = V then
                  Set_Text (Get_Entry (Combo), Nick (Val));
               end if;
               Show_All (Item);
               K := K + 1;
            end loop;

            Param_Handlers.Object_Connect
              (Get_List (Combo), "select_child",
               Param_Handlers.To_Marshaller (Enum_Changed'Access),
               Slot_Object => Combo,
               User_Data   => N);

            return Gtk_Widget (Combo);
         end;

      else
         declare
            Label : Gtk_Label;
         begin
            Gtk_New (Label, -"Preference cannot be edited");
            return Gtk_Widget (Label);
         end;
      end if;
   end Editor_Widget;

   -------------------------
   -- Reset_Specific_Data --
   -------------------------

   procedure Reset_Specific_Data (Node : Node_Ptr) is
      Sibling : Node_Ptr := Node;
   begin
      while Sibling /= null loop
         Sibling.Specific_Data := (Descr => null);
         Reset_Specific_Data (Sibling.Child);
         Sibling := Sibling.Next;
      end loop;
   end Reset_Specific_Data;

   ----------------------
   -- Edit_Preferences --
   ----------------------

   procedure Edit_Preferences
     (Manager           : access Preferences_Manager_Record;
      Parent            : access Gtk.Window.Gtk_Window_Record'Class;
      On_Changed        : Action_Callback)
   is
      Model             : Gtk_Tree_Store;
      Main_Table        : Gtk_Table;
      Current_Selection : Gtk_Table;
      Title             : Gtk_Label;

      function Find_Or_Create_Page (Name : String) return Gtk_Table;
      --  Return the iterator in Model matching Name. The page is created if
      --  needed.

      procedure Selection_Changed (Tree : access Gtk_Widget_Record'Class);
      --  Called when the selected page has changed.

      function Find_Or_Create_Page (Name : String) return Gtk_Table is
         Current : Gtk_Tree_Iter := Null_Iter;
         Child   : Gtk_Tree_Iter;
         First, Last : Integer := Name'First;
         Table   : Gtk_Table;

      begin
         while First <= Name'Last loop
            Last := First;
            while Last <= Name'Last and then Name (Last) /= ':' loop
               Last := Last + 1;
            end loop;

            if Current = Null_Iter then
               Child := Get_Iter_First (Model);
            else
               Child := Children (Model, Current);
            end if;

            while Child /= Null_Iter
              and then Get_String (Model, Child, 0) /= Name (First .. Last - 1)
            loop
               Next (Model, Child);
            end loop;

            if Child = Null_Iter then
               Gtk_New (Table, Rows => 0, Columns => 2,
                        Homogeneous => False);
               Set_Row_Spacings (Table, 1);
               Set_Col_Spacings (Table, 5);

               Append (Model, Child, Current);
               Set (Model, Child, 0, Name (First .. Last - 1));
               Set (Model, Child, 1, GObject (Table));

               Set_Child_Visible (Table, False);
               Attach (Main_Table, Table, 1, 2, 2, 3,
                       Ypadding => 0, Xpadding => 10);
            end if;

            Current := Child;

            First := Last + 1;
         end loop;

         return Gtk_Table (Get_Object (Model, Current, 1));
      end Find_Or_Create_Page;

      procedure Selection_Changed (Tree : access Gtk_Widget_Record'Class) is
         Iter : Gtk_Tree_Iter;
         M    : Gtk_Tree_Model;
      begin
         if Current_Selection /= null then
            Set_Child_Visible (Current_Selection, False);
            Current_Selection := null;
         end if;

         Get_Selected (Get_Selection (Gtk_Tree_View (Tree)), M, Iter);

         if Iter /= Null_Iter then
            Current_Selection := Gtk_Table (Get_Object (Model, Iter, 1));
            Set_Child_Visible (Current_Selection, True);
            Set_Text (Title, Get_String (Model, Iter, 0));
         end if;
      end Selection_Changed;

      Dialog     : Gtk_Dialog;
      Frame      : Gtk_Frame;
      Table      : Gtk_Table;
      View       : Gtk_Tree_View;
      Col        : Gtk_Tree_View_Column;
      Render     : Gtk_Cell_Renderer_Text;
      Num        : Gint;
      Scrolled   : Gtk_Scrolled_Window;

      Tmp        : Gtk_Widget;
      pragma Unreferenced (Tmp, Num);

      Prefs      : Preference_Information_Access := Manager.Default;
      Saved_Pref : Node_Ptr := Deep_Copy (Manager.Preferences);
      Had_Apply  : Boolean := False;
      Row        : Guint;
      Widget     : Gtk_Widget;
      Tips       : Gtk_Tooltips;
      Event      : Gtk_Event_Box;
      Label      : Gtk_Label;
      Color      : Gdk_Color;
      Separator  : Gtk_Separator;

   begin
      Gtk_New
        (Dialog => Dialog,
         Title  => -"Preferences",
         Parent => Gtk_Window (Parent),
         Flags  => Modal or Destroy_With_Parent);
      Set_Position (Dialog, Win_Pos_Mouse);
      Set_Default_Size (Dialog, 620, 400);
      Gtk_New (Tips);

      Gtk_New (Main_Table, Rows => 3, Columns => 2, Homogeneous => False);
      Pack_Start (Get_Vbox (Dialog), Main_Table);

      Gtk_New (Frame);
      Attach (Main_Table, Frame, 0, 1, 0, 3);

      Gtk_New (Event);
      Attach (Main_Table, Event, 1, 2, 0, 1, Yoptions => 0);
      Color := Parse ("#0e79bd");
      Alloc (Get_Default_Colormap, Color);
      Set_Style (Event, Copy (Get_Style (Event)));
      Set_Background (Get_Style (Event), State_Normal, Color);

      Gtk_New (Title, " ");
      Set_Alignment (Title, 0.1, 0.5);
      Add (Event, Title);

      Gtk_New_Hseparator (Separator);
      Attach (Main_Table, Separator, 1, 2, 1, 2, Yoptions => 0, Ypadding => 1);

      Gtk_New (Scrolled);
      Set_Policy (Scrolled, Policy_Never, Policy_Automatic);
      Add (Frame, Scrolled);

      Gtk_New (Model, (0 => GType_String, 1 => GType_Object));
      Gtk_New (View, Model);
      Set_Headers_Visible (View, False);

      Gtk_New (Col);
      Num := Append_Column (View, Col);
      Gtk_New (Render);
      Pack_Start (Col, Render, Expand => True);
      Add_Attribute (Col, Render, "text", 0);

      Widget_Callback.Object_Connect
        (Get_Selection (View), "changed",
         Widget_Callback.To_Marshaller (Selection_Changed'Unrestricted_Access),
         View);

      Add (Scrolled, View);

      while Prefs /= null loop
         if (Flags (Prefs.Param) and Param_Writable) /= 0 then
            Table := Find_Or_Create_Page (Get_Page (Manager, Prefs.Param));
            Row := Get_Property (Table, N_Rows_Property);
            Resize (Table, Rows =>  Row + 1, Columns => 2);

            Gtk_New (Event);
            Gtk_New (Label, Nick_Name (Prefs.Param));
            Add (Event, Label);
            Set_Tip (Tips, Event, Description (Prefs.Param));
            Set_Alignment (Label, 0.0, 0.5);
            Attach (Table, Event, 0, 1, Row, Row + 1,
                    Xoptions => Fill, Yoptions => 0);

            Widget := Editor_Widget (Manager, Prefs.Param, Tips);
            if Widget /= null then
               Attach (Table, Widget, 1, 2, Row, Row + 1, Yoptions => 0);
            end if;
         end if;

         Prefs := Prefs.Next;
      end loop;

      Tmp := Add_Button (Dialog, Stock_Ok, Gtk_Response_OK);
      Tmp := Add_Button (Dialog, Stock_Apply, Gtk_Response_Apply);
      Tmp := Add_Button (Dialog, Stock_Cancel, Gtk_Response_Cancel);

      Enable (Tips);

      Show_All (Dialog);

      Reset_Specific_Data (Manager.Preferences);

      loop
         case Run (Dialog) is
            when Gtk_Response_OK =>
               Free (Saved_Pref);
               Destroy (Dialog);
               if On_Changed /= null then
                  On_Changed (Manager);
               end if;
               exit;

            when Gtk_Response_Apply =>
               if On_Changed /= null then
                  On_Changed (Manager);
               end if;
               Had_Apply := True;

            when others =>  --  including Cancel
               Free (Manager.Preferences);
               Manager.Preferences := Saved_Pref;
               Destroy (Dialog);
               if Had_Apply and then On_Changed /= null then
                  On_Changed (Manager);
               end if;
               exit;
         end case;
      end loop;

      Destroy (Tips);

   exception
      when others =>
         Destroy (Dialog);
   end Edit_Preferences;

end Default_Preferences;
