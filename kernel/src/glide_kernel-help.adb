-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2001-2002                       --
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
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Glib;                      use Glib;
with Glib.Xml_Int;              use Glib.Xml_Int;
with Glib.Values;               use Glib.Values;
with Csc_HTML_Widget;           use Csc_HTML_Widget;
with GNAT.Directory_Operations; use GNAT.Directory_Operations;
with GNAT.OS_Lib;               use GNAT.OS_Lib;
with Glide_Kernel.Modules;      use Glide_Kernel.Modules;
with Glide_Kernel.Preferences;  use Glide_Kernel.Preferences;
with Gtkada.MDI;                use Gtkada.MDI;
with Gdk.Event;                 use Gdk.Event;
with Gdk.Types.Keysyms;         use Gdk.Types.Keysyms;
with Gtk.Adjustment;            use Gtk.Adjustment;
with Gtk.Enums;                 use Gtk.Enums;
with Gtk.Scrolled_Window;       use Gtk.Scrolled_Window;
with Gtk.Widget;                use Gtk.Widget;
with Gtkada.Handlers;           use Gtkada.Handlers;
with Glide_Intl;                use Glide_Intl;
with Traces;                    use Traces;
with OS_Utils;                  use OS_Utils;
with Ada.Strings.Fixed;         use Ada.Strings.Fixed;
with Ada.Exceptions;            use Ada.Exceptions;

package body Glide_Kernel.Help is

   Me : Debug_Handle := Create ("Glide_Kernel.Help");

   type Help_Browser_Record is new Gtk_Scrolled_Window_Record with record
      Current_Help_File : GNAT.OS_Lib.String_Access;
      --  The current help file displayed. Used to find relative (hyper) links.

      Csc : Csc_HTML;
   end record;
   type Help_Browser is access all Help_Browser_Record'Class;

   function Load_File
     (Kernel : access Kernel_Handle_Record'Class;
      Html   : access Help_Browser_Record'Class;
      File   : String) return Boolean;
   --  Load File in HTML widget, and set File as the Current_Help_File for
   --  Kernel. Return True if the file could be successfully read.

   procedure Url_Requested
     (Object : access Gtk_Widget_Record'Class;
      Params : Glib.Values.GValues);
   --  Handler for the url_requested signal
   --  Called when loading a url as part of another page display (e.g an
   --  image).

   procedure On_Url
     (Object : access Gtk_Widget_Record'Class;
      Params : Glib.Values.GValues);
   --  Handler for the on_url signal

   procedure Link_Clicked
     (Object : access Glib.Object.GObject_Record'Class;
      Params : Glib.Values.GValues;
      Kernel : Kernel_Handle);
   --  Handler for the link_clicked signal

   procedure Title_Changed
     (Object : access Glib.Object.GObject_Record'Class;
      Params : Glib.Values.GValues;
      Kernel : Kernel_Handle);
   --  Handler for the title_changed signal

   function Load_Desktop
     (Node : Node_Ptr; User : Kernel_Handle) return Gtk_Widget;
   function Save_Desktop
     (Widget : access Gtk.Widget.Gtk_Widget_Record'Class)
      return Node_Ptr;
   --  Support functions for the MDI

   function Mime_Action
     (Kernel    : access Kernel_Handle_Record'Class;
      Mime_Type : String;
      Data      : GValue_Array;
      Mode      : Mime_Mode := Read_Write) return Boolean;
   --  Process, if possible, the data sent by the kernel

   function Create_Html_Editor
     (Kernel : access Kernel_Handle_Record'Class; File : String)
      return Help_Browser;
   --  Create a new html editor that edits File.

   procedure Display_Help
     (Kernel    : access Kernel_Handle_Record'Class;
      Help_File : String);
   --  Display HTML Help file

   function Key_Press
     (Html : access Gtk_Widget_Record'Class;
      Event : Gdk_Event) return Boolean;
   --  Handles the scrolling through the keyboard keys

   ---------------
   -- Load_File --
   ---------------

   function Load_File
     (Kernel : access Kernel_Handle_Record'Class;
      Html   : access Help_Browser_Record'Class;
      File   : String) return Boolean
   is
      Buffer   : String_Access;
      Stream   : Csc_HTML_Stream;
      Success  : Boolean;

   begin
      Push_State (Kernel_Handle (Kernel), Busy);
      Buffer := Read_File (File);

      if Buffer /= null then
         Trace (Me, "loading file: " & File);
         Free (Html.Current_Help_File);
         Html.Current_Help_File := new String' (File);
         Stream := HTML_Begin (Html.Csc);
         HTML_Write (Html.Csc, Stream, Buffer.all);
         HTML_End (Html.Csc, Stream, Stream_OK);
         Free (Buffer);
         Success := True;
      else
         Trace (Me, "link not found: " & File);
         Success := False;
      end if;

      Pop_State (Kernel_Handle (Kernel));
      return Success;
   end Load_File;

   -------------------
   -- Url_Requested --
   -------------------

   procedure Url_Requested
     (Object : access Gtk_Widget_Record'Class;
      Params : Glib.Values.GValues)
   is
      Html   : Help_Browser := Help_Browser (Object);
      Url    : constant String := Get_String (Nth (Params, 1));
      Stream : Csc_HTML_Stream :=
        Csc_HTML_Stream (Get_Proxy (Nth (Params, 2)));
      Buffer : String_Access;

   begin
      Trace (Me, "url requested: " & Url);

      if Is_Absolute_Path (Url) then
         Buffer := Read_File (Url);
      else
         declare
            Base_Dir : constant String :=
              Dir_Name (Html.Current_Help_File.all);
         begin
            Buffer := Read_File (Base_Dir & Url);
            Trace (Me, "url normalized: " & Base_Dir & Url);
         end;
      end if;

      if Buffer /= null then
         Stream_Write (Stream, Buffer.all);
         Free (Buffer);
      end if;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end Url_Requested;

   ------------
   -- On_Url --
   ------------

   procedure On_Url
     (Object : access Gtk_Widget_Record'Class;
      Params : Glib.Values.GValues)
   is
      pragma Unreferenced (Object);
      --  Html     : Help_Browser := Help_Browser (Object);
      Url : constant String := Get_String (Nth (Params, 1));
   begin
      Trace (Me, "On_Url: " & Url);

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Url;

   ------------------
   -- Link_Clicked --
   ------------------

   procedure Link_Clicked
     (Object : access Glib.Object.GObject_Record'Class;
      Params : Glib.Values.GValues;
      Kernel : Kernel_Handle)
   is
      Html     : Help_Browser := Help_Browser (Object);
      Url      : constant String := Get_String (Nth (Params, 1));
      Result   : Boolean := True;
      Anchor   : Natural := Index (Url, "#");

   begin
      if Anchor = 0 then
         Anchor := Url'Last + 1;
      end if;

      if Is_Absolute_Path (Url) then
         if Url /= Html.Current_Help_File.all then
            Result := Load_File
              (Kernel, Html, Url (Url'First .. Anchor - 1));
         end if;
      else
         declare
            Base_Dir : constant String :=
              Dir_Name (Html.Current_Help_File.all);
            Basename : constant String :=
              Base_Name (Html.Current_Help_File.all);

         begin
            if Url (Url'First .. Anchor - 1) /= Basename then
               Result := Load_File
                 (Kernel, Html,
                  Base_Dir & Url (Url'First .. Anchor - 1));
            end if;
         end;
      end if;

      if Result and then Anchor < Url'Last then
         Push_State (Kernel_Handle (Kernel), Busy);
         Trace (Me, "jumping to anchor " & Url (Anchor .. Url'Last));
         Result := Jump_To_Anchor
           (Html.Csc, Url (Anchor + 1 .. Url'Last));
         Pop_State (Kernel_Handle (Kernel));
      end if;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end Link_Clicked;

   -------------------
   -- Title_Changed --
   -------------------

   procedure Title_Changed
     (Object : access Glib.Object.GObject_Record'Class;
      Params : Glib.Values.GValues;
      Kernel : Kernel_Handle)
   is
      pragma Unreferenced (Object);
      Title : constant String := Get_String (Nth (Params, 1));
      MDI   : constant MDI_Window := Get_MDI (Kernel);
      Child : MDI_Child;

   begin
      Child := Find_MDI_Child_By_Tag (MDI, Help_Browser_Record'Tag);

      if Child /= null then
         Set_Title (Child, (-"Help: ") & Title);
      end if;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end Title_Changed;

   ---------------
   -- Key_Press --
   ---------------

   function Key_Press
     (Html : access Gtk_Widget_Record'Class;
      Event : Gdk_Event) return Boolean
   is
      H : Help_Browser := Help_Browser (Html);
      Adj : Gtk_Adjustment;
   begin
      case Get_Key_Val (Event) is
         when GDK_Up =>
            Adj := Get_Vadjustment (H);
            Set_Value
              (Adj,
               Gdouble'Max
                 (Get_Lower (Adj),
                  Get_Value (Adj) - Get_Step_Increment (Adj)));

         when GDK_Down =>
            Adj := Get_Vadjustment (H);
            Set_Value
              (Adj,
               Gdouble'Min
                 (Get_Value (Adj) + Get_Step_Increment (Adj),
                  Get_Upper (Adj) - Get_Page_Size (Adj)));

         when GDK_Page_Up =>
            Adj := Get_Vadjustment (H);
            Set_Value
              (Adj,
               Gdouble'Max
                 (Get_Lower (Adj),
                  Get_Value (Adj) - Get_Page_Size (Adj)));

         when GDK_Page_Down =>
            Adj := Get_Vadjustment (H);
            Set_Value
              (Adj,
               Gdouble'Min
                 (Get_Value (Adj) + Get_Page_Size (Adj),
                  Get_Upper (Adj) - Get_Page_Size (Adj)));

         when others =>
            return False;
      end case;

      return True;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
         return True;
   end Key_Press;

   ------------------------
   -- Create_Html_Editor --
   ------------------------

   function Create_Html_Editor
     (Kernel : access Kernel_Handle_Record'Class; File : String)
      return Help_Browser
   is
      Html   : Help_Browser;
      Result : Boolean;
   begin
      Html := new Help_Browser_Record;
      Gtk.Scrolled_Window.Initialize (Html);
      Set_Policy (Html, Policy_Automatic, Policy_Always);
      Gtk_New (Html.Csc);
      Add (Html, Html.Csc);
      Set_Size_Request
        (Html,
         Get_Pref (Kernel, Default_Widget_Width),
         Get_Pref (Kernel, Default_Widget_Height));

      Widget_Callback.Object_Connect
        (Html.Csc, "url_requested", Url_Requested'Access, Slot_Object => Html);
      Kernel_Callback.Object_Connect
        (Html.Csc, "link_clicked",
         Link_Clicked'Access, User_Data => Kernel_Handle (Kernel),
         Slot_Object => Html);
      Widget_Callback.Object_Connect
        (Html.Csc, "on_url", On_Url'Access, Slot_Object => Html);
      Kernel_Callback.Object_Connect
        (Html.Csc, "title_changed",
         Title_Changed'Access, User_Data => Kernel_Handle (Kernel),
         Slot_Object => Html);
      Return_Callback.Object_Connect
        (Html.Csc, "key_press_event",
         Return_Callback.To_Marshaller (Key_Press'Access), Html);

      Result := Load_File (Kernel, Html, File);

      return Html;
   end Create_Html_Editor;

   ------------------
   -- Display_Help --
   ------------------

   procedure Display_Help
     (Kernel    : access Kernel_Handle_Record'Class;
      Help_File : String)
   is
      MDI      : constant MDI_Window := Get_MDI (Kernel);
      Scrolled : Help_Browser;
      Child    : MDI_Child;
      Result   : Boolean;

   begin
      Child := Find_MDI_Child_By_Tag (MDI, Help_Browser_Record'Tag);

      if Child = null then
         Scrolled := Create_Html_Editor (Kernel, Help_File);
         Child := Put (MDI, Scrolled);
         Set_Title (Child, -"Help");
         Show_All (Scrolled);
         Raise_Child (Child);

      else
         Scrolled := Help_Browser (Get_Widget (Child));

         if Scrolled.Current_Help_File /= null
           and then Help_File /= Scrolled.Current_Help_File.all
         then
            Result := Load_File (Kernel, Scrolled, Help_File);
         end if;

         Raise_Child (Child);
      end if;
   end Display_Help;

   ------------
   -- Search --
   ------------

   function Search
     (Kernel         : access Kernel_Handle_Record'Class;
      Text           : String;
      Case_Sensitive : Boolean := True;
      Forward        : Boolean := True;
      Regular        : Boolean := False) return Boolean
   is
      MDI      : constant MDI_Window := Get_MDI (Kernel);
      Child    : MDI_Child := Find_MDI_Child_By_Tag
        (MDI, Help_Browser_Record'Tag);
      Scrolled : Help_Browser;

   begin
      if Child = null then
         return False;
      end if;

      Scrolled := Help_Browser (Get_Widget (Child));
      return Search
        (Get_Engine (Scrolled.Csc), Text,
         Case_Sensitive, Forward, Regular);
   end Search;

   -----------------
   -- Search_Next --
   -----------------

   function Search_Next
     (Kernel : access Kernel_Handle_Record'Class) return Boolean
   is
      MDI      : constant MDI_Window := Get_MDI (Kernel);
      Child    : MDI_Child := Find_MDI_Child_By_Tag
        (MDI, Help_Browser_Record'Tag);
      Scrolled : Help_Browser;

   begin
      if Child = null then
         return False;
      end if;

      Scrolled := Help_Browser (Get_Widget (Child));
      return Search_Next (Get_Engine (Scrolled.Csc));
   end Search_Next;

   ------------------
   -- Load_Desktop --
   ------------------

   function Load_Desktop
     (Node : Node_Ptr; User : Kernel_Handle) return Gtk_Widget
   is
      Editor : Help_Browser;
      File   : Glib.String_Ptr;
   begin
      if Node.Tag.all = "Help_Browser" then
         File := Get_Field (Node, "File");
         if File /= null then
            Editor := Create_Html_Editor (User, File.all);
         end if;

         return Gtk_Widget (Editor);
      end if;
      return null;
   end Load_Desktop;

   ------------------
   -- Save_Desktop --
   ------------------

   function Save_Desktop
     (Widget : access Gtk.Widget.Gtk_Widget_Record'Class)
     return Node_Ptr
   is
      N, Child : Node_Ptr;
   begin
      if Widget.all in Help_Browser_Record'Class then
         N := new Node;
         N.Tag := new String' ("Help_Browser");

         Child := new Node;
         Child.Tag := new String' ("File");

         if Help_Browser (Widget).Current_Help_File = null then
            Child.Value := new String' ("");
         else
            Child.Value := new String'
              (Help_Browser (Widget).Current_Help_File.all);
         end if;

         Add_Child (N, Child);
         return N;
      end if;

      return null;
   end Save_Desktop;

   -----------------
   -- Mime_Action --
   -----------------

   function Mime_Action
     (Kernel    : access Kernel_Handle_Record'Class;
      Mime_Type : String;
      Data      : GValue_Array;
      Mode      : Mime_Mode := Read_Write) return Boolean
   is
      pragma Unreferenced (Mode);
   begin
      if Mime_Type = Mime_Html_File then
         declare
            File : constant String := Get_String (Data (Data'First));
         begin
            Display_Help (Kernel, File);
         end;

         return True;
      end if;

      return False;
   end Mime_Action;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module
     (Kernel : access Glide_Kernel.Kernel_Handle_Record'Class) is
   begin
      Register_Module
        (Module                  => Help_Module_ID,
         Kernel                  => Kernel,
         Module_Name             => Help_Module_Name,
         Priority                => Default_Priority,
         Contextual_Menu_Handler => null,
         Mime_Handler            => Mime_Action'Access);
      Glide_Kernel.Kernel_Desktop.Register_Desktop_Functions
        (Save_Desktop'Access, Load_Desktop'Access);
   end Register_Module;

end Glide_Kernel.Help;
