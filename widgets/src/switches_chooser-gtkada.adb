-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                   Copyright (C) 2007-2008, AdaCore                --
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
-- a copy of the GNU General Public License along with this library; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Glib;                   use Glib;
with Gtk.Adjustment;         use Gtk.Adjustment;
with Gtk.Box;                use Gtk.Box;
with Gtk.Button;             use Gtk.Button;
with Gtk.Check_Button;       use Gtk.Check_Button;
with Gtk.Combo;              use Gtk.Combo;
with Gtk.Dialog;             use Gtk.Dialog;
with Gtk.Editable;           use Gtk.Editable;
with Gtk.Enums;              use Gtk.Enums;
with Gtk.GEntry;             use Gtk.GEntry;
with Gtk.Frame;              use Gtk.Frame;
with Gtk.Handlers;           use Gtk.Handlers;
with Gtk.Label;              use Gtk.Label;
with Gtk.Radio_Button;       use Gtk.Radio_Button;
with Gtk.Scrolled_Window;    use Gtk.Scrolled_Window;
with Gtk.Size_Group;         use Gtk.Size_Group;
with Gtk.Spin_Button;        use Gtk.Spin_Button;
with Gtk.Stock;              use Gtk.Stock;
with Gtk.Table;              use Gtk.Table;
with Gtk.Toggle_Button;      use Gtk.Toggle_Button;
with Gtk.Tooltips;           use Gtk.Tooltips;
with Gtk.Object;             use Gtk.Object;
with Gtk.Widget;             use Gtk.Widget;
with Gtk.Window;             use Gtk.Window;
with Gtkada.File_Selector;   use Gtkada.File_Selector;
with Gtkada.Handlers;        use Gtkada.Handlers;
with Gtkada.Intl;            use Gtkada.Intl;
with GNATCOLL.VFS;                    use GNATCOLL.VFS;

package body Switches_Chooser.Gtkada is

   use Switch_Description_Vectors, Combo_Switch_Vectors;
   use Frame_Description_Vectors;

   type Switch_Data is record
      Editor : Switches_Editor;
      Switch : Switch_Description_Vectors.Extended_Index;
   end record;
   package User_Widget_Callback is new Gtk.Handlers.User_Callback
     (Gtk_Widget_Record, Switch_Data);

   type Popup_Button_Record is new Gtk_Button_Record with record
      Switch : Switch_Description_Vectors.Extended_Index;
   end record;
   type Popup_Button is access all Popup_Button_Record'Class;

   procedure On_Toggle_Check
     (Toggle : access Gtk_Widget_Record'Class;
      Data   : Switch_Data);
   procedure On_Field_Changed
     (Field  : access Gtk_Widget_Record'Class;
      Data   : Switch_Data);
   procedure On_Combo_Changed
     (Combo  : access Gtk_Widget_Record'Class;
      Data   : Switch_Data);
   procedure On_Spin_Changed
     (Spin   : access Gtk_Widget_Record'Class;
      Data   : Switch_Data);
   procedure On_Popup_Button_Clicked
     (Pop    : access Gtk_Widget_Record'Class;
      Data   : Switch_Data);
   procedure On_Destroy
     (Widget : access Gtk_Widget_Record'Class;
      Data   : Switch_Data);
   procedure On_Command_Line_Changed
     (Editor : access Gtk_Widget_Record'Class);
   --  Called when some of the widgets change

   procedure Destroy_Dialog (Dialog : access Gtk_Widget_Record'Class);
   --  Called to destroy a popup dialog

   procedure On_Dialog_Destroy (Pop : access Gtk_Widget_Record'Class);
   --  Called when a popup dialog is destroyed

   procedure Browse_Directory
     (Field  : access Gtk_Widget_Record'Class;
      Data   : Switch_Data);
   procedure Browse_File
     (Field : access Gtk_Widget_Record'Class;
      Data   : Switch_Data);
   --  Open a dialog to select a directory or a file

   procedure Create_Box_For_Popup
     (Editor             : access Switches_Editor_Record'Class;
      Popup              : Popup_Index;
      Table              : access Gtk_Table_Record'Class;
      Lines, Columns     : Positive);
   --  Create, inside Table, the frames that contain the switches associated
   --  with the given popup (or main window).

   procedure Create_Widget
     (Editor   : access Switches_Editor_Record'Class;
      Switch   : Switch_Description_Vectors.Cursor;
      Size     : Gtk_Size_Group;
      Box      : Gtk_Box);
   --  Create and register the widget matching S.

   procedure Set_Tooltip
     (Editor   : access Switches_Editor_Record'Class;
      W        : access Gtk_Widget_Record'Class;
      Switch   : Switch_Description_Vectors.Cursor;
      S        : Switch_Description);
   --  Set the tooltip on W

   --------------------------------
   -- Set_Graphical_Command_Line --
   --------------------------------

   procedure Set_Graphical_Command_Line
     (Editor    : in out Switches_Editor_Record;
      Cmd_Line  : String) is
   begin
      Set_Text (Editor.Ent, Cmd_Line);
   end Set_Graphical_Command_Line;

   ---------------------
   -- On_Toggle_Check --
   ---------------------

   procedure On_Toggle_Check
     (Toggle : access Gtk_Widget_Record'Class;
      Data   : Switch_Data)
   is
   begin
      Change_Switch
        (Data.Editor.all, Toggle,
         Parameter => Boolean'Image (Get_Active (Gtk_Check_Button (Toggle))));
   end On_Toggle_Check;

   --------------------
   -- Destroy_Dialog --
   --------------------

   procedure Destroy_Dialog (Dialog : access Gtk_Widget_Record'Class) is
   begin
      Destroy (Dialog);
   end Destroy_Dialog;

   -----------------------
   -- On_Dialog_Destroy --
   -----------------------

   procedure On_Dialog_Destroy
     (Pop    : access Gtk_Widget_Record'Class)
   is
   begin
      Set_Sensitive (Pop, True);
   end On_Dialog_Destroy;

   -----------------------------
   -- On_Popup_Button_Clicked --
   -----------------------------

   procedure On_Popup_Button_Clicked
     (Pop    : access Gtk_Widget_Record'Class;
      Data   : Switch_Data)
   is
      Dialog : Gtk_Dialog;
      Table  : Gtk_Table;
      Config   : constant Switches_Editor_Config := Get_Config (Data.Editor);
      S        : constant Switch_Description :=
        Element (Config.Switches, Popup_Button (Pop).Switch);
      Tmp      : Gtk_Widget;
      Flags    : Gtk_Dialog_Flags := 0;
   begin
      --  If the parent window is modal, we need to make the popup modal as
      --  well, since otherwise the user will not be able to click on any of
      --  its children.
      if Get_Modal (Gtk_Window (Get_Toplevel (Data.Editor))) then
         Flags := Modal;
      end if;

      Gtk_New (Dialog,
               Title  => To_String (S.Label),
               Parent => Gtk_Window (Get_Toplevel (Data.Editor)),
               Flags  => Flags);
      Set_Sensitive (Pop, False);

      Gtk_New
        (Table,
         Rows        => Guint (S.Lines),
         Columns     => Guint (S.Columns),
         Homogeneous => False);
      Pack_Start (Get_Vbox (Dialog), Table);
      Create_Box_For_Popup
        (Editor    => Data.Editor,
         Popup     => S.To_Popup,
         Table     => Table,
         Lines     => S.Lines,
         Columns   => S.Columns);
      Gtk_Switches_Editors.On_Command_Line_Changed (Data.Editor.all);

      Tmp := Add_Button (Dialog, Stock_Ok, Gtk_Response_OK);
      Show_All (Dialog);

      Widget_Callback.Object_Connect
        (Tmp, Gtk.Button.Signal_Clicked,
         Destroy_Dialog'Access, Dialog);
      Widget_Callback.Object_Connect
        (Dialog, Gtk.Object.Signal_Destroy,
         On_Dialog_Destroy'Access, Pop);
   end On_Popup_Button_Clicked;

   ----------------------
   -- On_Field_Changed --
   ----------------------

   procedure On_Field_Changed
     (Field  : access Gtk_Widget_Record'Class;
      Data   : Switch_Data) is
   begin
      Change_Switch (Data.Editor.all, Field, Get_Text (Gtk_Entry (Field)));
   end On_Field_Changed;

   ----------------------
   -- On_Combo_Changed --
   ----------------------

   procedure On_Combo_Changed
     (Combo  : access Gtk_Widget_Record'Class;
      Data   : Switch_Data) is
   begin
      Change_Switch
        (Data.Editor.all, Combo, Get_Text (Get_Entry (Gtk_Combo (Combo))));
   end On_Combo_Changed;

   ---------------------
   -- On_Spin_Changed --
   ---------------------

   procedure On_Spin_Changed
     (Spin   : access Gtk_Widget_Record'Class;
      Data   : Switch_Data)
   is
      V : constant String :=
        Gint'Image (Get_Value_As_Int (Gtk_Spin_Button (Spin)));
   begin
      if V (V'First) = ' ' then
         Change_Switch (Data.Editor.all, Spin, V (V'First + 1 .. V'Last));
      else
         Change_Switch (Data.Editor.all, Spin, V);
      end if;
   end On_Spin_Changed;

   -----------------------------
   -- On_Command_Line_Changed --
   -----------------------------

   procedure On_Command_Line_Changed
     (Editor : access Gtk_Widget_Record'Class)
   is
   begin
      On_Command_Line_Changed
        (Switches_Editor (Editor).all,
         Get_Text (Switches_Editor (Editor).Ent));
   end On_Command_Line_Changed;

   --------------------------
   -- Set_Graphical_Widget --
   --------------------------

   procedure Set_Graphical_Widget
     (Editor    : in out Switches_Editor_Record;
      Widget    : access Gtk.Widget.Gtk_Widget_Record'Class;
      Switch    : Switch_Type;
      Parameter : String)
   is
      pragma Unreferenced (Editor);
   begin
      case Switch is
         when Switch_Check | Switch_Radio =>
            Set_Active (Gtk_Check_Button (Widget), Boolean'Value (Parameter));

         when Switch_Field =>
            Set_Text (Gtk_Entry (Widget), Parameter);

         when Switch_Spin =>
            Set_Value (Gtk_Spin_Button (Widget), Gdouble'Value (Parameter));

         when Switch_Combo =>
            Set_Text (Get_Entry (Gtk_Combo (Widget)), Parameter);

         when Switch_Popup =>
            null;
      end case;
   end Set_Graphical_Widget;

   ----------------------
   -- Browse_Directory --
   ----------------------

   procedure Browse_Directory
     (Field  : access Gtk_Widget_Record'Class;
      Data   : Switch_Data)
   is
      F   : constant Gtk_Entry := Gtk_Entry (Field);
      Dir : constant Virtual_File := Select_Directory
        (Base_Directory    => Create (Get_Text (F)),
         Parent            => Gtk_Window (Get_Toplevel (F)),
         Use_Native_Dialog => Data.Editor.Native_Dialogs);
   begin
      if Dir /= GNATCOLL.VFS.No_File then
         Set_Text (F, Full_Name (Dir).all);
      end if;
   end Browse_Directory;

   -----------------
   -- Browse_File --
   -----------------

   procedure Browse_File
     (Field  : access Gtk_Widget_Record'Class;
      Data   : Switch_Data)
   is
      F    : constant Gtk_Entry := Gtk_Entry (Field);
      VF   : constant Virtual_File := Create (Get_Text (F));
      File : constant Virtual_File := Select_File
        (Base_Directory    => Dir (VF),
         Default_Name      => Display_Base_Name (VF),
         Parent            => Gtk_Window (Get_Toplevel (F)),
         Kind              => Open_File,
         File_Pattern      => "*;*.ad?;{*.c,*.h,*.cpp,*.cc,*.C}",
         Pattern_Name      => -"All files;Ada files;C/C++ files",
         Use_Native_Dialog => Data.Editor.Native_Dialogs);
   begin
      if File /= GNATCOLL.VFS.No_File then
         Set_Text (F, Full_Name (File).all);
      end if;
   end Browse_File;

   ----------------
   -- On_Destroy --
   ----------------

   procedure On_Destroy
     (Widget : access Gtk_Widget_Record'Class;
      Data   : Switch_Data)
   is
      pragma Unreferenced (Widget);
   begin
      Set_Widget (Data.Editor.all, Data.Switch, null);
   end On_Destroy;

   -----------------
   -- Set_Tooltip --
   -----------------

   procedure Set_Tooltip
     (Editor   : access Switches_Editor_Record'Class;
      W        : access Gtk_Widget_Record'Class;
      Switch   : Switch_Description_Vectors.Cursor;
      S        : Switch_Description)
   is
   begin
      Set_Widget (Editor.all, To_Index (Switch), Gtk_Widget (W));
      User_Widget_Callback.Connect
        (W, Gtk.Object.Signal_Destroy, On_Destroy'Access,
         (Switches_Editor (Editor), To_Index (Switch)));
      if S.Tip /= "" then
         Set_Tip
           (Editor.Tooltips, W,
            '(' & To_String (S.Switch) & ") " & ASCII.LF
            & To_String (S.Tip));
      else
         Set_Tip (Editor.Tooltips, W, '(' & To_String (S.Switch) & ") ");
      end if;
   end Set_Tooltip;

   -------------------
   -- Create_Widget --
   -------------------

   procedure Create_Widget
     (Editor   : access Switches_Editor_Record'Class;
      Switch   : Switch_Description_Vectors.Cursor;
      Size     : Gtk_Size_Group;
      Box      : Gtk_Box)
   is
      S : constant Switch_Description := Element (Switch);
      Check    : Gtk_Check_Button;
      Field    : Gtk_Entry;
      Label    : Gtk_Label;
      Spin     : Gtk_Spin_Button;
      Adj      : Gtk_Adjustment;
      Radio    : Gtk_Radio_Button;
      Hbox     : Gtk_Box;
      Button   : Gtk_Button;
      Combo    : Gtk_Combo;
      Combo_Iter : Combo_Switch_Vectors.Cursor;
      Switch2  : Switch_Description_Vectors.Cursor;
      List     : Gtk.Enums.String_List.Glist;
      Pop      : Popup_Button;

   begin
      if S.Typ /= Switch_Check
        and then S.Typ /= Switch_Radio
        and then S.Typ /= Switch_Popup
      then
         Gtk_New_Hbox  (Hbox, False, 0);
         Pack_Start    (Box, Hbox, Expand => False);
         Gtk_New       (Label, To_String (S.Label));
         Pack_Start    (Hbox, Label, Expand => False);
         Set_Alignment (Label, 0.0, 0.5);
         Add_Widget    (Size, Label);
      end if;

      case S.Typ is
         when Switch_Check =>
            Gtk_New    (Check, To_String (S.Label));
            Pack_Start (Box, Check, Expand => False);
            Set_Tooltip (Editor, Check, Switch, S);
            User_Widget_Callback.Connect
              (Check, Gtk.Toggle_Button.Signal_Toggled,
               On_Toggle_Check'Access,
               (Switches_Editor (Editor), To_Index (Switch)));

         when Switch_Field =>
            Gtk_New (Field);
            Set_Tooltip (Editor, Field, Switch, S);
            Pack_Start (Hbox, Field, True, True, 0);
            User_Widget_Callback.Connect
              (Field, Gtk.Editable.Signal_Changed,
               On_Field_Changed'Access,
               (Switches_Editor (Editor), To_Index (Switch)));

            if S.As_File then
               Gtk_New (Button, -"Browse");
               Pack_Start (Hbox, Button, Expand => False);
               User_Widget_Callback.Object_Connect
                 (Button, Signal_Clicked, Browse_File'Access,
                  Slot_Object => Field, User_Data =>
                    (Switches_Editor (Editor), To_Index (Switch)));

            elsif S.As_Directory then
               Gtk_New (Button, -"Browse");
               Pack_Start (Hbox, Button, Expand => False);
               User_Widget_Callback.Object_Connect
                 (Button, Signal_Clicked,
                  Browse_Directory'Access,
                  Slot_Object => Field, User_Data =>
                    (Switches_Editor (Editor), To_Index (Switch)));
            end if;

         when Switch_Spin =>
            Gtk_New (Adj, Gdouble (S.Default),
                     Gdouble (S.Min), Gdouble (S.Max),
                     1.0, 10.0, 10.0);
            Gtk_New (Spin, Adj, 1.0, 0);
            Set_Tooltip (Editor, Spin, Switch, S);
            Pack_Start (Hbox, Spin, True, True, 0);

            User_Widget_Callback.Connect
              (Spin, Gtk.Spin_Button.Signal_Value_Changed,
               On_Spin_Changed'Access,
               (Switches_Editor (Editor), To_Index (Switch)));

         when Switch_Radio =>
            if S.Label = Null_Unbounded_String then
               --  Find all buttons in that group
               Switch2 := Next (Switch);
               while Has_Element (Switch2) loop
                  declare
                     S2 : constant Switch_Description := Element (Switch2);
                  begin
                     if S2.Typ = Switch_Radio
                       and then S2.Group = S.Group
                     then
                        Gtk_New
                          (Radio, Group => Radio,
                           Label => To_String (S2.Label));
                        Pack_Start (Box, Radio, Expand => False);
                        Set_Tooltip (Editor, Radio, Switch2, S2);
                        User_Widget_Callback.Connect
                          (Radio, Gtk.Toggle_Button.Signal_Toggled,
                           On_Toggle_Check'Access,
                           (Switches_Editor (Editor), To_Index (Switch)));
                     end if;
                  end;

                  Next (Switch2);
               end loop;
            end if;

         when Switch_Combo =>
            Gtk_New (Combo);
            Set_Tooltip (Editor, Combo, Switch, S);
            Pack_Start (Hbox, Combo, True, True, 0);

            Combo_Iter := First (S.Entries);
            while Has_Element (Combo_Iter) loop
               Gtk.Enums.String_List.Append
                 (List, To_String (Element (Combo_Iter).Label));
               Next (Combo_Iter);
            end loop;

            Set_Popdown_Strings (Combo, List);

            User_Widget_Callback.Object_Connect
              (Get_Entry (Combo), Gtk.Editable.Signal_Changed,
               On_Combo_Changed'Access, Combo,
               (Switches_Editor (Editor), To_Index (Switch)));

         when Switch_Popup =>
            Pop := new Popup_Button_Record'
              (Gtk_Button_Record with
               Switch => To_Index (Switch));

            Gtk_New_Hbox  (Hbox, False, 0);
            Gtk_New       (Label, To_String (S.Label) & ": ");
            Pack_Start    (Hbox, Label, Expand => True, Fill => True);
            Set_Alignment (Label, 0.0, 0.5);

            Gtk_New       (Label, "...");
            Set_Alignment (Label, 1.0, 0.5);
            Pack_End      (Hbox, Label, Expand => True, Fill => True);

            Gtk.Button.Initialize (Pop, "");
            Add (Pop, Hbox);
            Pack_Start (Box, Pop, False);
            User_Widget_Callback.Connect
              (Pop, Gtk.Button.Signal_Clicked,
               On_Popup_Button_Clicked'Access,
               (Switches_Editor (Editor), To_Index (Switch)));

      end case;
   end Create_Widget;

   --------------------------
   -- Create_Box_For_Popup --
   --------------------------

   procedure Create_Box_For_Popup
     (Editor             : access Switches_Editor_Record'Class;
      Popup              : Popup_Index;
      Table              : access Gtk_Table_Record'Class;
      Lines, Columns     : Positive)
   is
      Config   : constant Switches_Editor_Config := Get_Config (Editor);
      Size     : Gtk_Size_Group;
      F        : Gtk_Frame;
      Scrolled : Gtk_Scrolled_Window;
      Switch   : Switch_Description_Vectors.Cursor;
      Box      : Gtk_Box;
      Frame_C  : Frame_Description_Vectors.Cursor;
      Frame    : Frame_Description;
      Col_Span, Line_Span : Positive;
   begin
      for L in 1 .. Lines loop
         for C in 1 .. Columns loop
            Switch := First (Config.Switches);
            Box := null;

            while Has_Element (Switch) loop
               declare
                  S : constant Switch_Description := Element (Switch);
               begin
                  --  Radio buttons are made of radio entries, which should not
                  --  be displayed explicitely (they will be displayed as part
                  --  of the radio button itself)
                  if (S.Typ /= Switch_Radio
                    or else S.Label = Null_Unbounded_String)
                    and then S.Popup = Popup
                    and then S.Line = L
                    and then S.Column = C
                  then
                     if Box = null then
                        Gtk_New (F);
                        Set_Border_Width (F, 5);
                        Col_Span := 1;
                        Line_Span := 1;

                        Frame_C := First (Config.Frames);
                        while Has_Element (Frame_C) loop
                           Frame := Element (Frame_C);
                           if Frame.Popup = Popup
                             and then Frame.Line = L
                             and then Frame.Column = C
                           then
                              Set_Label (F, To_String (Frame.Title));
                              Col_Span  := Frame.Col_Span;
                              Line_Span := Frame.Line_Span;
                              exit;
                           end if;
                           Next (Frame_C);
                        end loop;

                        Attach
                          (Table, F,
                           Guint (C - 1),
                           Guint (C - 1 + Col_Span),
                           Guint (L - 1),
                           Guint (L - 1 + Line_Span));

                        Gtk_New_Vbox (Box, False, 0);

                        if Config.Scrolled_Window then
                           Gtk_New (Scrolled);
                           Set_Policy
                             (Scrolled, Policy_Automatic, Policy_Automatic);
                           Set_Shadow_Type (Scrolled, Shadow_None);
                           Add_With_Viewport (Scrolled, Box);
                           Add (F, Scrolled);
                        else
                           Add (F, Box);
                        end if;

                        Gtk_New (Size);
                     end if;

                     Create_Widget
                       (Editor   => Editor,
                        Switch   => Switch,
                        Size     => Size,
                        Box      => Box);
                  end if;
               end;
               Next (Switch);
            end loop;
         end loop;
      end loop;
   end Create_Box_For_Popup;

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New
     (Editor             : out Switches_Editor;
      Config             : Switches_Editor_Config;
      Tooltips           : Gtk.Tooltips.Gtk_Tooltips;
      Use_Native_Dialogs : Boolean) is
   begin
      Editor := new Switches_Editor_Record;
      Initialize (Editor, Config, Tooltips, Use_Native_Dialogs);
   end Gtk_New;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (Editor             : access Switches_Editor_Record'Class;
      Config             : Switches_Editor_Config;
      Tooltips           : Gtk.Tooltips.Gtk_Tooltips;
      Use_Native_Dialogs : Boolean) is
   begin
      Editor.Native_Dialogs := Use_Native_Dialogs;
      Editor.Tooltips       := Tooltips;
      Initialize (Editor.all, Config);
      Gtk.Table.Initialize
        (Editor,
         Rows        => Guint (Config.Lines) + 1,
         Columns     => Guint (Config.Columns),
         Homogeneous => False);
      Create_Box_For_Popup
        (Editor    => Editor,
         Popup     => Main_Window,
         Table     => Editor,
         Lines     => Config.Lines,
         Columns   => Config.Columns);

      Gtk_New (Editor.Ent);
      if Config.Show_Command_Line then
         Attach (Editor, Editor.Ent,
                 0, Guint (Config.Columns),
                 Guint (Config.Lines), Guint (Config.Lines) + 1,
                 Yoptions => 0);
         Widget_Callback.Object_Connect
           (Editor.Ent, Gtk.Editable.Signal_Changed,
            Widget_Callback.To_Marshaller (On_Command_Line_Changed'Access),
            Editor);
      end if;

      On_Command_Line_Changed (Editor.all, "");
   end Initialize;

end Switches_Chooser.Gtkada;
