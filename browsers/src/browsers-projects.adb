------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                     Copyright (C) 2001-2014, AdaCore                     --
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
------------------------------------------------------------------------------

with Ada.Strings.Unbounded;     use Ada.Strings.Unbounded;
with Glib;                      use Glib;
with Glib.Object;               use Glib.Object;
with Gtk.Stock;                 use Gtk.Stock;
with Gtk.Toolbar;               use Gtk.Toolbar;
with Gtk.Widget;                use Gtk.Widget;
with Gtkada.Canvas_View;        use Gtkada.Canvas_View;
with Gtkada.Canvas_View.Views;  use Gtkada.Canvas_View.Views;
with Gtkada.MDI;                use Gtkada.MDI;
with Gtkada.Style;              use Gtkada.Style;

with Generic_Views;          use Generic_Views;
with GNATCOLL.Projects;      use GNATCOLL.Projects;
with GNATCOLL.Traces;        use GNATCOLL.Traces;
with GPS.Kernel;             use GPS.Kernel;
with GPS.Kernel.Contexts;    use GPS.Kernel.Contexts;
with GPS.Kernel.MDI;         use GPS.Kernel.MDI;
with GPS.Kernel.Modules;     use GPS.Kernel.Modules;
with GPS.Kernel.Modules.UI;  use GPS.Kernel.Modules.UI;
with GPS.Kernel.Project;     use GPS.Kernel.Project;
with GPS.Search;             use GPS.Search;
with GPS.Intl;               use GPS.Intl;
with Projects;               use Projects;
with Browsers.Canvas;        use Browsers.Canvas;
with Commands.Interactive;   use Commands, Commands.Interactive;

package body Browsers.Projects is

   Me : constant Trace_Handle := Create ("Browsers.Projects");

   type Project_Browser_Module is new Module_ID_Record with null record;

   ---------------------
   -- Project_Browser --
   ---------------------

   type Project_Browser_Record is new Browsers.Canvas.General_Browser_Record
   with null record;

   overriding procedure Create_Toolbar
     (View    : not null access Project_Browser_Record;
      Toolbar : not null access Gtk.Toolbar.Gtk_Toolbar_Record'Class);
   overriding procedure Filter_Changed
     (Self    : not null access Project_Browser_Record;
      Pattern : in out GPS.Search.Search_Pattern_Access);

   function Initialize
     (View   : access Project_Browser_Record'Class)
      return Gtk_Widget;
   --  Initialize the browser, and return the focus widget

   package Project_Views is new Generic_Views.Simple_Views
     (Module_Name            => "Project_Browser",
      View_Name              => -"Project Browser",
      Formal_View_Record     => Project_Browser_Record,
      Formal_MDI_Child       => GPS_MDI_Child_Record,
      Reuse_If_Exist         => True,
      Initialize             => Initialize,
      Local_Toolbar          => True,
      Local_Config           => True,
      Position               => Position_Automatic,
      Group                  => Group_Default);
   subtype Project_Browser is Project_Views.View_Access;
   use type Project_Browser;

   procedure Examine_Project_Hierarchy
     (Browser   : not null access Project_Browser_Record'Class;
      Project   : Project_Type;
      Recursive : Boolean);
   --  Display the project hierarchy for Project in the canvas.
   --  If Recursive is True, then the projects imported indirectly are also
   --  displayed.

   procedure Examine_Ancestor_Project_Hierarchy
     (Browser : not null access Project_Browser_Record'Class;
      Project : Project_Type);
   --  Add to the browser all the projects that with Project

   --------------
   -- Commands --
   --------------

   type Imported_By_Command is new Interactive_Command with record
      Recursive      : Boolean := False;
      Show_Ancestors : Boolean := False;
   end record;
   overriding function Execute
     (Command : access Imported_By_Command;
      Context : Interactive_Command_Context) return Command_Return_Type;

   ------------------
   -- Browser_Item --
   ------------------

   type Project_Item_Record is new GPS_Item_Record with record
      Name : Ada.Strings.Unbounded.Unbounded_String;
      --  Store the name, and not the project, in case the latter becomes
      --  invalid after we reload a project

      Circle : Ellipse_Item;
      --  Might be set or not (depends on the chosen draw mode)
   end record;
   type Project_Item is access all Project_Item_Record'Class;

   procedure Gtk_New
     (V       : out Project_Item;
      Browser : not null access Project_Browser_Record'Class;
      Project : Project_Type);
   --  Create a new project vertex

   function Add_Project_If_Not_Present
     (Browser : not null access Project_Browser_Record'Class;
      Project : Project_Type) return Project_Item;
   --  Add a new item for Project if there is currently none in the browser

   function Project_Of
     (Self : not null access Project_Item_Record'Class) return Project_Type;
   --  Return the project associated with Item

   function Find_Project
     (Browser      : not null access Project_Browser_Record'Class;
      Project_Name : String) return Project_Item;
   --  Return the first item representing Project_Name

   overriding procedure Set_Context
     (Item    : not null access Project_Item_Record;
      Context : in out Selection_Context);
   --  Set the GPS context from a selected item.

   type Show_Importing_Projects_Button is new Left_Arrow_Record
   with null record;
   overriding procedure On_Click
     (Self : not null access Show_Importing_Projects_Button;
      View : not null access GPS_Canvas_View_Record'Class);

   type Show_Imported_Projects_Button is new Right_Arrow_Record
   with null record;
   overriding procedure On_Click
     (Self : not null access Show_Imported_Projects_Button;
      View : not null access GPS_Canvas_View_Record'Class);

   -------------------
   -- Browser links --
   -------------------

   procedure Gtk_New_Link
     (L               : out GPS_Link;
      Browser         : not null access Project_Browser_Record'Class;
      Src, Dest       : not null access Abstract_Item_Record'Class;
      Is_Limited_With : Boolean := False;
      Extending       : Boolean := False);
   --  Create a new link

   procedure Add_Link_If_Not_Present
     (Browser      : not null access Project_Browser_Record'Class;
      Src, Dest    : Project_Item;
      Limited_With : Boolean);
   --  Add a link between the two items

   --------------------
   -- Create_Toolbar --
   --------------------

   overriding procedure Create_Toolbar
     (View    : not null access Project_Browser_Record;
      Toolbar : not null access Gtk.Toolbar.Gtk_Toolbar_Record'Class)
   is
   begin
      General_Browser_Record (View.all).Create_Toolbar (Toolbar); --  inherited
      View.Build_Filter
        (Toolbar     => Toolbar,
         Hist_Prefix => "project_browser",
         Tooltip     => -"Filter the contents of the project browser",
         Placeholder => -"filter",
         Options   => Has_Regexp or Has_Negate or Has_Whole_Word or Has_Fuzzy);
   end Create_Toolbar;

   ----------------
   -- Project_Of --
   ----------------

   function Project_Of (Self : not null access Project_Item_Record'Class)
      return Project_Type is
   begin
      return Get_Registry (Self.Browser.Kernel).Tree
        .Project_From_Name (To_String (Self.Name));
   end Project_Of;

   ------------------
   -- Find_Project --
   ------------------

   function Find_Project
     (Browser      : not null access Project_Browser_Record'Class;
      Project_Name : String) return Project_Item
   is
      Result : Project_Item;

      procedure On_Item (Item : not null access Abstract_Item_Record'Class);
      procedure On_Item (Item : not null access Abstract_Item_Record'Class) is
      begin
         if Item.all in Project_Item_Record'Class
           and then Project_Item (Item).Name = Project_Name
         then
            Result := Project_Item (Item);
         end if;
      end On_Item;

   begin
      Browser.Get_View.Model.For_Each_Item
        (On_Item'Access, Filter => Kind_Item);
      return Result;
   end Find_Project;

   --------------------------------
   -- Add_Project_If_Not_Present --
   --------------------------------

   function Add_Project_If_Not_Present
     (Browser : not null access Project_Browser_Record'Class;
      Project : Project_Type) return Project_Item
   is
      V : Project_Item := Find_Project (Browser, Project.Name);
   begin
      if V = null then
         Gtk_New (V, Browser, Project);
         V.Set_Position (No_Position);
         Browser_Model (Browser.Get_View.Model).Add (V);
      end if;

      return V;
   end Add_Project_If_Not_Present;

   ------------------
   -- Gtk_New_Link --
   ------------------

   procedure Gtk_New_Link
     (L               : out GPS_Link;
      Browser         : not null access Project_Browser_Record'Class;
      Src, Dest       : not null access Abstract_Item_Record'Class;
      Is_Limited_With : Boolean := False;
      Extending       : Boolean := False)
   is
      S  : constant access Browser_Styles := Browser.Get_View.Get_Styles;
      L2 : constant GPS_Link := new GPS_Link_Record;
   begin
      if Is_Limited_With then
         L2.Default_Style := S.Link2;
         Initialize
           (L2,
            From        => Src,
            To          => Dest,
            Routing     => Curve,
            Label       => Gtk_New_Text (S.Title, "limited"),
            Anchor_From => (X => 1.0, others => <>),
            Anchor_To   => (X => 0.0, others => <>),
            Style       => L2.Default_Style);
      elsif Extending then
         L2.Default_Style := S.Link2;
         Initialize
           (L2,
            From        => Src,
            To          => Dest,
            Routing     => Curve,
            Label       => Gtk_New_Text (S.Title, "extending"),
            Anchor_From => (X => 1.0, others => <>),
            Anchor_To   => (X => 0.0, others => <>),
            Style       => L2.Default_Style);
      else
         L2.Default_Style := S.Link;
         Initialize
           (L2,
            From        => Src,
            To          => Dest,
            Routing     => Curve,
            Anchor_From => (X => 1.0, others => <>),
            Anchor_To   => (X => 0.0, others => <>),
            Style       => L2.Default_Style);
      end if;
      L := L2;
   end Gtk_New_Link;

   -----------------------------
   -- Add_Link_If_Not_Present --
   -----------------------------

   procedure Add_Link_If_Not_Present
     (Browser      : not null access Project_Browser_Record'Class;
      Src, Dest    : Project_Item;
      Limited_With : Boolean)
   is
      L      : GPS_Link;
      P1, P2 : Project_Type;
      S1, S2 : access Abstract_Item_Record'Class;

   begin
      if not Browser.Has_Link (Src, Dest) then
         P1 := Project_Of (Src);
         P2 := Project_Of (Dest);

         S1 := (if Src.Circle = null then Src else Src);
         S2 := (if Dest.Circle = null then Dest else Dest);

         Gtk_New_Link
           (L, Browser, S1, S2,
            Is_Limited_With => Limited_With,
            Extending       => Extended_Project (P1) = P2);
         Browser_Model (Browser.Get_View.Model).Add (L);
      end if;
   end Add_Link_If_Not_Present;

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New
     (V       : out Project_Item;
      Browser : not null access Project_Browser_Record'Class;
      Project : Project_Type)
   is
      Contents : access Container_Item_Record'Class;
      S     : constant access Browser_Styles := Browser.Get_View.Get_Styles;
   begin
      V := new Project_Item_Record;
      V.Browser := General_Browser (Browser);
      V.Name := To_Unbounded_String (Project.Name);

      if True then
         V.Initialize_Rect (Style => S.Invisible);
         V.Set_Child_Layout (Horizontal_Stack);

         V.Circle := Gtk_New_Ellipse
           (Style => S.Circle, Width => 8.0, Height => 8.0);
         V.Add_Child (V.Circle);

         Contents := Gtk_New_Text (Style => S.Label, Text  => Project.Name);
         V.Add_Child (Contents, Margin => (0.0, 0.0, 0.0, 3.0));
      else
         V.Initialize_Rect (Style => S.Item, Radius => 5.0);
         Setup_Titlebar
           (V, Browser, Name => Project.Name,
            Left  => new Show_Importing_Projects_Button,
            Right => new Show_Imported_Projects_Button);

         if Project.Is_Aggregate_Project then
            Contents := Gtk_New_Text (S.Text_Font, "<<aggregate>>");
         else
            Contents := Gtk_New_Rect (S.Text_Font, Height => 1.0);
         end if;

         V.Add_Child (Contents, Margin => (2.0, 2.0, 2.0, 2.0));
      end if;
   end Gtk_New;

   -------------------------------
   -- Examine_Project_Hierarchy --
   -------------------------------

   procedure Examine_Project_Hierarchy
     (Browser   : not null access Project_Browser_Record'Class;
      Project   : Project_Type;
      Recursive : Boolean)
   is
      Src   : Project_Item;
      Items : Items_Lists.List;

      procedure Process_Project (Local : Project_Type; Src : Project_Item);
      --  Display all the imported projects from Local.
      --  Src is the item associated with Local

      ---------------------
      -- Process_Project --
      ---------------------

      procedure Process_Project (Local : Project_Type; Src : Project_Item) is
         Iter : Project_Iterator;
         Dest : Project_Item;
      begin
         --  If we are displaying the recursive hierarchy for the root project,
         --  we know that there won't be remaining ancestor projects, so we can
         --  make it clear for the user.
         Iter := Start (Local, Recursive => True, Direct_Only => True);
         while Current (Iter) /= No_Project loop
            if Current (Iter) /= Local then
               Dest := Add_Project_If_Not_Present (Browser, Current (Iter));
               Items.Append (Abstract_Item (Dest));
               Add_Link_If_Not_Present
                 (Browser, Src, Dest, Limited_With => Is_Limited_With (Iter));
            end if;
            Next (Iter);
         end loop;
      end Process_Project;

      Src2 : Project_Item;
      Iter : Project_Iterator;

   begin
      Trace (Me, "Examine_Project_Hierarchy for " & Project.Name
             & " Recursive=" & Recursive'Img);

      Src := Add_Project_If_Not_Present (Browser, Project);

      if Recursive then
         Iter := Start (Project, Recursive => True, Direct_Only => False);
         while Current (Iter) /= No_Project loop
            Src2 := Add_Project_If_Not_Present (Browser, Current (Iter));
            Items.Append (Abstract_Item (Src2));
            Process_Project (Current (Iter), Src2);
            Next (Iter);
         end loop;
      else
         Process_Project (Project, Src);
      end if;

      Browser.Get_View.Model.Clear_Selection;
      Browser.Get_View.Model.Add_To_Selection (Src);

      if Recursive then
         Browser.Get_View.Model.Refresh_Layout;
      else
         Insert_And_Layout_Items
           (Browser.Get_View,
            Ref         => Src,
            Items       => Items,
            Direction   => (if Browser.Horizontal_Layout then Right else Down),
            Space_Between_Items  => Space_Between_Items,
            Space_Between_Layers => Space_Between_Layers,
            Duration             => 0.3);
      end if;
   end Examine_Project_Hierarchy;

   ----------------------------------------
   -- Examine_Ancestor_Project_Hierarchy --
   ----------------------------------------

   procedure Examine_Ancestor_Project_Hierarchy
     (Browser : not null access Project_Browser_Record'Class;
      Project : Project_Type)
   is
      Src, Dest : Project_Item;
      Iter      : Project_Iterator;
      Items     : Items_Lists.List;
   begin
      Trace (Me, "Examine_Ancestor_Project_Hierarchy for " & Project.Name);

      Dest := Add_Project_If_Not_Present (Browser, Project);

      Iter := Find_All_Projects_Importing
        (Project      => Project,
         Include_Self => False,
         Direct_Only  => True);

      while Current (Iter) /= No_Project loop
         Src := Add_Project_If_Not_Present (Browser, Current (Iter));
         Items.Append (Abstract_Item (Src));
         Add_Link_If_Not_Present
           (Browser, Src, Dest,
            Limited_With => Is_Limited_With (Iter));
         Next (Iter);
      end loop;

      Browser.Get_View.Model.Clear_Selection;
      Browser.Get_View.Model.Add_To_Selection (Dest);

      Insert_And_Layout_Items
        (Browser.Get_View,
         Ref               => Dest,
         Items             => Items,
         Direction         => (if Browser.Horizontal_Layout then Left else Up),
         Space_Between_Items  => Space_Between_Items,
         Space_Between_Layers => Space_Between_Layers,
         Duration             => 0.3);
   end Examine_Ancestor_Project_Hierarchy;

   --------------
   -- On_Click --
   --------------

   overriding procedure On_Click
     (Self : not null access Show_Imported_Projects_Button;
      View : not null access GPS_Canvas_View_Record'Class)
   is
      pragma Unreferenced (View);
      Prj : constant Project_Item := Project_Item (Self.Get_Toplevel_Item);
   begin
      Examine_Project_Hierarchy
        (Project_Browser (Prj.Browser), Project_Of (Prj), Recursive => False);
   end On_Click;

   --------------
   -- On_Click --
   --------------

   overriding procedure On_Click
     (Self : not null access Show_Importing_Projects_Button;
      View : not null access GPS_Canvas_View_Record'Class)
   is
      pragma Unreferenced (View);
      Prj : constant Project_Item := Project_Item (Self.Get_Toplevel_Item);
   begin
      Examine_Ancestor_Project_Hierarchy
        (Browser => Project_Browser (Prj.Browser),
         Project => Project_Of (Prj));
   end On_Click;

   -----------------
   -- Set_Context --
   -----------------

   overriding procedure Set_Context
     (Item    : not null access Project_Item_Record;
      Context : in out Selection_Context)
   is
   begin
      Set_File_Information (Context, Project => Item.Project_Of);
   end Set_Context;

   ----------------
   -- Initialize --
   ----------------

   function Initialize
     (View   : access Project_Browser_Record'Class)
      return Gtk_Widget
   is
   begin
      Initialize (View, Use_Canvas_View => True);
      Register_Contextual_Menu
        (Kernel          => View.Kernel,
         Event_On_Widget => View,
         Object          => View,
         ID              => Project_Views.Get_Module,
         Context_Func    => Default_Browser_Context_Factory'Access);
      return Gtk_Widget (View);
   end Initialize;

   --------------------
   -- Filter_Changed --
   --------------------

   overriding procedure Filter_Changed
     (Self    : not null access Project_Browser_Record;
      Pattern : in out GPS.Search.Search_Pattern_Access)
   is
      use Item_Sets;

      Show_On_Match : constant Boolean := False;
      --  If True: when items do not match, they are left visible.
      --  Otherwise, they are hidden, along with their related links.

      To_Hide : Item_Sets.Set;

      procedure On_Item (Item : not null access Abstract_Item_Record'Class);
      procedure On_Item (Item : not null access Abstract_Item_Record'Class) is
         It : constant Project_Item := Project_Item (Item);
      begin
         if Pattern.Start (To_String (It.Name)) = GPS.Search.No_Match then
            Self.Get_View.Model.Include_Related_Items (Item, To_Hide);
         end if;
      end On_Item;

      procedure Set_Visible
        (Item : not null access Abstract_Item_Record'Class);
      procedure Set_Visible
        (Item : not null access Abstract_Item_Record'Class)
      is
      begin
         if To_Hide.Contains (Abstract_Item (Item)) then
            if Show_On_Match then
               Item.Hide;
            elsif Item.all in GPS_Item_Record'Class then
               GPS_Item (Item).Outline := Outline_None;
            end if;
         elsif Pattern = null then
            if Show_On_Match then
               Item.Show;
            elsif Item.all in GPS_Item_Record'Class then
               GPS_Item (Item).Outline := Outline_None;
            end if;
         else
            if Show_On_Match then
               Item.Show;
            elsif Item.all in GPS_Item_Record'Class then
               GPS_Item (Item).Outline := Outline_As_Match;
            end if;
         end if;
      end Set_Visible;

   begin
      if Pattern /= null then
         Self.Get_View.Model.For_Each_Item
           (On_Item'Access, Filter => Kind_Item);
      end if;

      Self.Get_View.Model.For_Each_Item (Set_Visible'Access);
      Self.Get_View.Queue_Draw;
   end Filter_Changed;

   -------------
   -- Execute --
   -------------

   overriding function Execute
     (Command : access Imported_By_Command;
      Context : Interactive_Command_Context) return Command_Return_Type
   is
      Browser : constant Project_Browser :=
        Project_Views.Get_Or_Create_View (Get_Kernel (Context.Context));
   begin
      if Command.Show_Ancestors then
         Examine_Ancestor_Project_Hierarchy
           (Browser,
            Project_Information (Context.Context));
      else
         Examine_Project_Hierarchy
           (Browser,
            Project_Information (Context.Context),
            Recursive => Command.Recursive);
      end if;
      return Commands.Success;
   end Execute;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class)
   is
      Command : Interactive_Command_Access;
      Project_Browser_Module_ID : Module_ID;
   begin
      Project_Browser_Module_ID := new Project_Browser_Module;
      Project_Views.Register_Module
        (Kernel, Project_Browser_Module_ID);

      Command := new Imported_By_Command;
      Register_Contextual_Menu
        (Kernel, "Show projects imported",
         Label       => -"Show projects imported by %p",
         Stock_Image => Stock_Go_Forward,
         Action      => Command,
         Filter      => Lookup_Filter (Kernel, "Project only"));

      Command := new Imported_By_Command;
      Imported_By_Command (Command.all).Recursive := True;
      Register_Contextual_Menu
        (Kernel, "Show recursive projects imported",
         Label  => -"Show projects imported by %p recursively",
         Action => Command,
         Filter => Lookup_Filter (Kernel, "Project only"));

      Command := new Imported_By_Command;
      Imported_By_Command (Command.all).Show_Ancestors := True;
      Register_Contextual_Menu
        (Kernel, "Show projects importing",
         Label  => -"Show projects depending on %p",
         Stock_Image => Stock_Go_Back,
         Action => Command,
         Filter => Lookup_Filter (Kernel, "Project only"));
   end Register_Module;

end Browsers.Projects;
