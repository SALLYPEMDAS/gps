-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2003                            --
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

with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with GNAT.OS_Lib;          use GNAT.OS_Lib;
with Glib.Object;          use Glib.Object;
with Glide_Intl;           use Glide_Intl;
with Glide_Kernel.Modules; use Glide_Kernel.Modules;
with Glide_Kernel.Project; use Glide_Kernel.Project;
with Src_Info.Queries;     use Src_Info, Src_Info.Queries;
with String_Hash;
with System;               use System;
with String_Utils;         use String_Utils;
with Projects;             use Projects;
with Projects.Registry;    use Projects.Registry;
with Projects.Editor;      use Projects.Editor;
with Types;                use Types;

package body Glide_Kernel.Scripts is

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (Class_Instance_Record'Class, Class_Instance);

   type Scripting_Language_Data;
   type Scripting_Language_List is access Scripting_Language_Data;
   type Scripting_Language_Data is record
      Script : Scripting_Language;
      Next   : Scripting_Language_List;
   end record;

   procedure Free (Class : in out Class_Type);
   package Classes_Hash is new String_Hash (Class_Type, Free, No_Class);
   use Classes_Hash.String_Hash_Table;

   type Scripting_Data_Record is new Kernel_Scripting_Data_Record with record
      Scripting_Languages : Scripting_Language_List;
      Classes             : Classes_Hash.String_Hash_Table.HTable;
      Entity_Class        : Class_Type := No_Class;
      File_Class          : Class_Type := No_Class;
      Project_Class       : Class_Type := No_Class;
   end record;
   type Scripting_Data is access all Scripting_Data_Record'Class;

   type Entity_Information_Access is access Entity_Information;
   function Convert is new Ada.Unchecked_Conversion
     (System.Address, Entity_Information_Access);
   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (Entity_Information, Entity_Information_Access);
   procedure On_Destroy_Entity (Value : System.Address);
   pragma Convention (C, On_Destroy_Entity);

   type File_Info_Access is access all File_Info;
   function Convert is new Ada.Unchecked_Conversion
     (System.Address, File_Info_Access);
   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (File_Info, File_Info_Access);
   procedure On_Destroy_File (Value : System.Address);
   pragma Convention (C, On_Destroy_File);

   procedure Default_Command_Handler
     (Data : in out Callback_Data'Class; Command : String);
   --  Handler for the default commands

   procedure Create_Entity_Command_Handler
     (Data : in out Callback_Data'Class; Command : String);
   --  Handler for the "create_entity" command

   procedure Create_File_Command_Handler
     (Data : in out Callback_Data'Class; Command : String);
   --  Handler for the "create_file" command

   procedure Create_Project_Command_Handler
     (Data : in out Callback_Data'Class; Command : String);
   --  Handler for the "create_project" command

   ----------
   -- Free --
   ----------

   procedure Free (Class : in out Class_Type) is
   begin
      Free (Class.Name);
   end Free;

   ---------------------------------
   -- Register_Scripting_Language --
   ---------------------------------

   procedure Register_Scripting_Language
     (Kernel  : access Glide_Kernel.Kernel_Handle_Record'Class;
      Script  : access Scripting_Language_Record'Class) is
   begin
      Scripting_Data (Kernel.Scripts).Scripting_Languages :=
        new Scripting_Language_Data'
          (Script => Scripting_Language (Script),
           Next   => Scripting_Data (Kernel.Scripts).Scripting_Languages);
   end Register_Scripting_Language;

   -------------------------------
   -- Lookup_Scripting_Language --
   -------------------------------

   function Lookup_Scripting_Language
     (Kernel  : access Glide_Kernel.Kernel_Handle_Record'Class;
      Name    : String) return Scripting_Language
   is
      Tmp : Scripting_Language_List :=
        Scripting_Data (Kernel.Scripts).Scripting_Languages;
   begin
      while Tmp /= null loop
         if Get_Name (Tmp.Script) = Name then
            return Tmp.Script;
         end if;

         Tmp := Tmp.Next;
      end loop;

      return null;
   end Lookup_Scripting_Language;

   ----------------------
   -- Register_Command --
   ----------------------

   procedure Register_Command
     (Kernel       : access Glide_Kernel.Kernel_Handle_Record'Class;
      Command      : String;
      Usage        : String;
      Description  : String;
      Minimum_Args : Natural := 0;
      Maximum_Args : Natural := 0;
      Handler      : Module_Command_Function;
      Class        : Class_Type := No_Class)
   is
      Tmp : Scripting_Language_List :=
        Scripting_Data (Kernel.Scripts).Scripting_Languages;
   begin
      while Tmp /= null loop
         Register_Command
           (Tmp.Script, Command, Usage, Description,
            Minimum_Args, Maximum_Args, Handler, Class);
         Tmp := Tmp.Next;
      end loop;
   end Register_Command;

   ---------------
   -- New_Class --
   ---------------

   function New_Class
     (Kernel        : access Glide_Kernel.Kernel_Handle_Record'Class;
      Name          : String;
      Description   : String := "";
      As_Dictionary : Boolean := False) return Class_Type
   is
      Tmp   : Scripting_Language_List :=
        Scripting_Data (Kernel.Scripts).Scripting_Languages;
      Class : Class_Type;

   begin
      Class := Get (Scripting_Data (Kernel.Scripts).Classes, Name);

      if Class = No_Class then
         while Tmp /= null loop
            Register_Class (Tmp.Script, Name, Description, As_Dictionary);
            Tmp := Tmp.Next;
         end loop;

         Class := Class_Type'(Name => new String'(Name));
         Set (Scripting_Data (Kernel.Scripts).Classes, Name, Class);
      end if;

      return Class;
   end New_Class;

   --------------
   -- Get_Name --
   --------------

   function Get_Name (Class : Class_Type) return String is
   begin
      if Class.Name = null then
         return "";
      else
         return Class.Name.all;
      end if;
   end Get_Name;

   ----------
   -- Free --
   ----------

   procedure Free (Instance : access Class_Instance_Record'Class) is
      Ins : Class_Instance := Class_Instance (Instance);
   begin
      Primitive_Free (Instance.all);
      Unchecked_Free (Ins);
   end Free;

   -----------------------
   -- On_Destroy_Entity --
   -----------------------

   procedure On_Destroy_Entity (Value : System.Address) is
      Ent : Entity_Information_Access := Convert (Value);
   begin
      Destroy (Ent.all);
      Unchecked_Free (Ent);
   end On_Destroy_Entity;

   ----------
   -- Free --
   ----------

   procedure Free (File : in out File_Info) is
   begin
      Free (File.Name);
   end Free;

   ---------------------
   -- On_Destroy_File --
   ---------------------

   procedure On_Destroy_File (Value : System.Address) is
      File : File_Info_Access := Convert (Value);
   begin
      Free (File.all);
      Unchecked_Free (File);
   end On_Destroy_File;

   --------------
   -- Set_Data --
   --------------

   procedure Set_Data
     (Instance : access Class_Instance_Record'Class;
      Entity   : Entity_Information)
   is
      Ent : constant Entity_Information_Access :=
        new Entity_Information'(Copy (Entity));
      Script : constant Scripting_Language := Get_Script (Instance);
   begin
      if not Is_Subclass
        (Script, Get_Class (Instance), Get_Entity_Class (Get_Kernel (Script)))
      then
         raise Invalid_Data;
      end if;

      Set_Data
        (Instance,
         Value      => Ent.all'Address,
         On_Destroy => On_Destroy_Entity'Access);
   end Set_Data;

   --------------
   -- Get_Data --
   --------------

   function Get_Data (Instance : access Class_Instance_Record'Class)
      return Entity_Information
   is
      Script : constant Scripting_Language := Get_Script (Instance);
      Ent : Entity_Information_Access;
   begin
      if not Is_Subclass
        (Script, Get_Class (Instance), Get_Entity_Class (Get_Kernel (Script)))
      then
         raise Invalid_Data;
      end if;

      Ent := Convert (Get_Data (Instance));
      return Ent.all;
   end Get_Data;

   --------------
   -- Set_Data --
   --------------

   procedure Set_Data
     (Instance : access Class_Instance_Record'Class;
      File     : File_Info)
   is
      Ent    : File_Info_Access;
      Script : constant Scripting_Language := Get_Script (Instance);
   begin
      if not Is_Subclass
        (Script, Get_Class (Instance), Get_File_Class (Get_Kernel (Script)))
      then
         raise Invalid_Data;
      end if;

      Ent      := new File_Info;
      Ent.Name := new String'(Get_Name (File));

      Set_Data
        (Instance,
         Value      => Ent.all'Address,
         On_Destroy => On_Destroy_File'Access);
   end Set_Data;

   --------------
   -- Get_Data --
   --------------

   function Get_Data (Instance : access Class_Instance_Record'Class)
      return File_Info
   is
      Ent : File_Info_Access;
      Script : constant Scripting_Language := Get_Script (Instance);
   begin
      if not Is_Subclass
        (Script, Get_Class (Instance), Get_File_Class (Get_Kernel (Script)))
      then
         raise Invalid_Data;
      end if;

      Ent := Convert (Get_Data (Instance));
      return Ent.all;
   end Get_Data;

   --------------
   -- Set_Data --
   --------------

   procedure Set_Data
     (Instance : access Class_Instance_Record'Class;
      Project  : Project_Type)
   is
      Script : constant Scripting_Language := Get_Script (Instance);
   begin
      if not Is_Subclass
        (Script, Get_Class (Instance), Get_Project_Class (Get_Kernel (Script)))
      then
         raise Invalid_Data;
      end if;

      Set_Data (Instance, Value => Integer (Name_Id'(Project_Name (Project))));
   end Set_Data;

   --------------
   -- Get_Data --
   --------------

   function Get_Data (Instance : access Class_Instance_Record'Class)
      return Project_Type
   is
      Script : constant Scripting_Language := Get_Script (Instance);
   begin
      if not Is_Subclass
        (Script, Get_Class (Instance), Get_Project_Class (Get_Kernel (Script)))
      then
         raise Invalid_Data;
      end if;

      return Get_Project_From_Name
        (Project_Registry (Get_Registry (Get_Kernel (Script))),
         Name_Id (Integer'(Get_Data (Instance))));
   end Get_Data;

   -----------------------------
   -- Default_Command_Handler --
   -----------------------------

   procedure Default_Command_Handler
     (Data    : in out Callback_Data'Class;
      Command : String)
   is
      Kernel : constant Kernel_Handle := Get_Kernel (Data);
   begin
      if Command = "insmod" then
         declare
            Shared  : constant String := Nth_Arg (Data, 1);
            Module  : constant String := Nth_Arg (Data, 2);
            Success : Boolean;
         begin
            Dynamic_Register_Module (Kernel, Shared, Module, Success);
            if Success then
               Set_Return_Value (Data, -"Module successfully loaded.");
            else
               Set_Return_Value (Data, -"Couldn't load module.");
            end if;
         end;

      elsif Command = "lsmod" then
         declare
            use type Module_List.List_Node;
            Current : Module_List.List_Node;
            List    : constant Module_List.List := List_Of_Modules (Kernel);
         begin
            Current := Module_List.First (List);

            Set_Return_Value_As_List (Data);
            while Current /= Module_List.Null_Node loop
               Set_Return_Value
                 (Data,
                  Module_Name (Module_List.Data (Current)));
               Current := Module_List.Next (Current);
            end loop;
         end;
      end if;
   end Default_Command_Handler;

   -----------------------------------
   -- Create_Entity_Command_Handler --
   -----------------------------------

   procedure Create_Entity_Command_Handler
     (Data : in out Callback_Data'Class; Command : String)
   is
      pragma Unreferenced (Command);
      Kernel : constant Kernel_Handle := Get_Kernel (Data);
      Name   : constant String  := Nth_Arg (Data, 1);
      File   : constant String  := Nth_Arg (Data, 2);
      L      : constant Integer := Nth_Arg (Data, 3, Default => 1);
      C      : constant Integer := Nth_Arg (Data, 4, Default => 1);
      Status : Find_Decl_Or_Body_Query_Status;
      Entity : Entity_Information;
      Instance : Class_Instance;
      Lib_Info : LI_File_Ptr;
   begin
      Lib_Info := Locate_From_Source_And_Complete (Kernel, File);
      if Lib_Info = No_LI_File then
         Set_Error_Msg (Data, -"File not found " & File);
         return;
      end if;

      Find_Declaration_Or_Overloaded
        (Kernel      => Kernel,
         Lib_Info    => Lib_Info,
         File_Name   => File,
         Entity_Name => Name,
         Line        => L,
         Column      => C,
         Entity      => Entity,
         Status      => Status);

      if Status /= Success and then Status /= Fuzzy_Match then
         Set_Error_Msg (Data, -"Entity not found");
      else
         Instance := New_Instance (Data, Get_Entity_Class (Kernel));
         Set_Data (Instance, Entity);
         Destroy (Entity);
         Set_Return_Value (Data, Instance);
      end if;
   end Create_Entity_Command_Handler;

   ---------------------------------
   -- Create_File_Command_Handler --
   ---------------------------------

   procedure Create_File_Command_Handler
     (Data : in out Callback_Data'Class; Command : String)
   is
      pragma Unreferenced (Command);
      Kernel   : constant Kernel_Handle := Get_Kernel (Data);
      Name     : constant String := Nth_Arg (Data, 1);
      Instance : constant Class_Instance := New_Instance
        (Data, Get_File_Class (Kernel));
      Info     : File_Info := (Name => new String'(Name));
   begin
      Set_Data (Instance, Info);
      Free (Info);
      Set_Return_Value (Data, Instance);
   end Create_File_Command_Handler;

   ------------------------------------
   -- Create_Project_Command_Handler --
   ------------------------------------

   procedure Create_Project_Command_Handler
     (Data : in out Callback_Data'Class; Command : String)
   is
      pragma Unreferenced (Command);
      Kernel   : constant Kernel_Handle := Get_Kernel (Data);
      Name     : constant String := Nth_Arg (Data, 1);
      Instance : Class_Instance;
      Project  : constant Project_Type := Get_Project_From_Name
        (Project_Registry (Get_Registry (Kernel)), Get_String (Name));
   begin
      if Project = No_Project then
         Set_Error_Msg (Data, -"No such project: " & Name);
      else
         Instance := New_Instance (Data, Get_Project_Class (Kernel));
         Set_Data (Instance, Project);
         Set_Return_Value (Data, Instance);
      end if;
   end Create_Project_Command_Handler;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (Kernel : access Glide_Kernel.Kernel_Handle_Record'Class) is
   begin
      Kernel.Scripts := new Scripting_Data_Record;
   end Initialize;

   --------------------------------------
   -- Register_Default_Script_Commands --
   --------------------------------------

   procedure Register_Default_Script_Commands
     (Kernel : access Glide_Kernel.Kernel_Handle_Record'Class) is
   begin
      Register_Command
        (Kernel,
         Command      => "insmod",
         Usage        => "insmod (shared-lib, module) -> None",
         Description  => -"Dynamically register from shared-lib a new module.",
         Minimum_Args => 2,
         Maximum_Args => 2,
         Handler      => Default_Command_Handler'Access);

      Register_Command
        (Kernel,
         Command      => "lsmod",
         Usage        => "lsmod () -> list of modules",
         Description  => -"List modules currently loaded.",
         Minimum_Args => 0,
         Maximum_Args => 0,
         Handler      => Default_Command_Handler'Access);

      Register_Command
        (Kernel,
         Command      => "get_entity",
         Usage        =>
           "get_entity (entity_name, file_name, [line], [column]) -> Entity",
         Description  =>
           -"Create a new entity, from any of its references.",
         Minimum_Args => 2,
         Maximum_Args => 4,
         Handler      => Create_Entity_Command_Handler'Access);

      Register_Command
        (Kernel,
         Command      => "get_file",
         Usage        => "get_file (file_name) -> File",
         Description  => -"Create a new file, from its name.",
         Minimum_Args => 1,
         Maximum_Args => 1,
         Handler      => Create_File_Command_Handler'Access);

      Register_Command
        (Kernel,
         Command      => "get_project",
         Usage        => "get_project (name) -> Project",
         Description  => -"Create a project handle, from its name.",
         Minimum_Args => 1,
         Maximum_Args => 1,
         Handler      => Create_Project_Command_Handler'Access);
   end Register_Default_Script_Commands;

   ----------------------
   -- Get_Entity_Class --
   ----------------------

   function Get_Entity_Class
     (Kernel : access Glide_Kernel.Kernel_Handle_Record'Class)
      return Class_Type is
   begin
      if Scripting_Data (Kernel.Scripts).Entity_Class = No_Class then
         Scripting_Data (Kernel.Scripts).Entity_Class := New_Class
           (Kernel,
            "Entity", "Represents an entity from the source, based on the"
            & " location of its declaration");
      end if;
      return Scripting_Data (Kernel.Scripts).Entity_Class;
   end Get_Entity_Class;

   --------------------
   -- Get_File_Class --
   --------------------

   function Get_File_Class
     (Kernel : access Glide_Kernel.Kernel_Handle_Record'Class)
      return Class_Type is
   begin
      if Scripting_Data (Kernel.Scripts).File_Class = No_Class then
         Scripting_Data (Kernel.Scripts).File_Class := New_Class
           (Kernel,
            "File", "Represents a source file of your application");
      end if;
      return Scripting_Data (Kernel.Scripts).File_Class;
   end Get_File_Class;

   -----------------------
   -- Get_Project_Class --
   -----------------------

   function Get_Project_Class
     (Kernel : access Glide_Kernel.Kernel_Handle_Record'Class)
      return Class_Type is
   begin
      if Scripting_Data (Kernel.Scripts).Project_Class = No_Class then
         Scripting_Data (Kernel.Scripts).Project_Class := New_Class
           (Kernel, "Project", "Represents a project file");
      end if;
      return Scripting_Data (Kernel.Scripts).Project_Class;
   end Get_Project_Class;

   -------------------------------
   -- Execute_GPS_Shell_Command --
   -------------------------------

   function Execute_GPS_Shell_Command
     (Kernel  : access Glide_Kernel.Kernel_Handle_Record'Class;
      Command : String;
      Args    : GNAT.OS_Lib.Argument_List := No_Args) return String is
   begin
      return Execute_Command
        (Lookup_Scripting_Language (Kernel, GPS_Shell_Name), Command, Args);
   end Execute_GPS_Shell_Command;

   -------------------------------
   -- Execute_GPS_Shell_Command --
   -------------------------------

   procedure Execute_GPS_Shell_Command
     (Kernel  : access Glide_Kernel.Kernel_Handle_Record'Class;
      Command : String;
      Args    : GNAT.OS_Lib.Argument_List := No_Args)
   is
      Str : constant String := Execute_Command
        (Lookup_Scripting_Language (Kernel, GPS_Shell_Name), Command, Args);
      pragma Unreferenced (Str);
   begin
      null;
   end Execute_GPS_Shell_Command;

   ---------------------
   -- Execute_Command --
   ---------------------

   function Execute_Command
     (Script  : access Scripting_Language_Record;
      Command : String;
      Args    : GNAT.OS_Lib.Argument_List) return String
   is
      Cmd : constant String := Command & ' '
        & Argument_List_To_String (Args);
   begin
      Execute_Command
        (Scripting_Language (Script), Cmd, Display_In_Console => False);
      return "";
   end Execute_Command;

   --------------
   -- Get_Name --
   --------------

   function Get_Name (File : File_Info) return String is
   begin
      if File.Name /= null then
         return File.Name.all;
      else
         return "";
      end if;
   end Get_Name;

   -------------
   -- Nth_Arg --
   -------------

   function Nth_Arg
     (Data : Callback_Data; N : Positive; Default : String)
      return String is
   begin
      if N > Number_Of_Arguments (Callback_Data'Class (Data)) then
         return Default;
      else
         return Nth_Arg (Callback_Data'Class (Data), N);
      end if;
   end Nth_Arg;

   -------------
   -- Nth_Arg --
   -------------

   function Nth_Arg
     (Data : Callback_Data; N : Positive; Default : Integer)
      return Integer is
   begin
      if N > Number_Of_Arguments (Callback_Data'Class (Data)) then
         return Default;
      else
         return Nth_Arg (Callback_Data'Class (Data), N);
      end if;
   end Nth_Arg;

   -------------
   -- Nth_Arg --
   -------------

   function Nth_Arg
     (Data : Callback_Data; N : Positive; Default : Boolean)
      return Boolean is
   begin
      if N > Number_Of_Arguments (Callback_Data'Class (Data)) then
         return Default;
      else
         return Nth_Arg (Callback_Data'Class (Data), N);
      end if;
   end Nth_Arg;

   -------------
   -- Nth_Arg --
   -------------

   function Nth_Arg
     (Data    : Callback_Data;
      N       : Positive;
      Default : System.Address)
      return System.Address is
   begin
      if N > Number_Of_Arguments (Callback_Data'Class (Data)) then
         return Default;
      else
         return Nth_Arg (Callback_Data'Class (Data), N);
      end if;
   end Nth_Arg;

   -------------
   -- Nth_Arg --
   -------------

   function Nth_Arg
     (Data    : Callback_Data;
      N       : Positive;
      Class   : Class_Type;
      Default : Class_Instance)
      return Class_Instance is
   begin
      if N > Number_Of_Arguments (Callback_Data'Class (Data)) then
         return Default;
      else
         return Nth_Arg (Callback_Data'Class (Data), N, Class);
      end if;
   end Nth_Arg;

end Glide_Kernel.Scripts;
