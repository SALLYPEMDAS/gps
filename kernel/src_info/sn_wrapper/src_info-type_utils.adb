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

with GNAT.Regpat; use GNAT.Regpat;
with GNAT.OS_Lib; use GNAT.OS_Lib;
with SN.Find_Fns; use SN.Find_Fns;
with Ada.Unchecked_Deallocation;

package body Src_Info.Type_Utils is

   Function_Type_Pat : constant Pattern_Matcher :=
     Compile ("\(([^\)]+)\)\s*\(\)\s*$");
   --  Regexp used to cut functional type definition
   --  example: int (*[]) ()
   --                ^^^ this is cut

   Template_Type_Pat : constant Pattern_Matcher :=
     Compile ("^([^<\s]+)\s*<");
   --  Regexp to find plain class name in the templatized
   --  name.

   procedure Free (HT : in out HTable);
   --  Frees Module_Typedefs

   ------------------------
   -- Type_Hash_Function --
   ------------------------

   function Type_Hash_Function (Key : String_Access)
      return String_Hash_Table_Range
   is
      function String_Hash_Function is
         new HTables.Hash (String_Hash_Table_Range);
      pragma Inline (String_Hash_Function);
   begin
      return String_Hash_Function (Key.all);
   end Type_Hash_Function;

   -------------------------
   -- Type_Equal_Function --
   -------------------------

   function Type_Equal_Function (K1, K2 : String_Access)
      return Boolean
   is
   begin
      return K1.all = K2.all;
   end Type_Equal_Function;

   ----------
   -- Free --
   ----------

   procedure Free (HT : in out HTable) is
      Elmt : Typedef_Entry;
      Key  : String_Access;
   begin
      Get_First (HT, Elmt);
      loop
         exit when Elmt.Key = null;
         Key := Elmt.Key;
         Remove (HT, Key);
         Free (Key);
         Get_Next (HT, Elmt);
      end loop;
   end Free;

   ----------
   -- Free --
   ----------

   procedure Free (Desc : in out CType_Description) is
   begin
      if Desc.Parent_Point /= Invalid_Point then
         Free (Desc.Parent_Filename);
      end if;
      if Desc.Ancestor_Point /= Invalid_Point then
         Free (Desc.Ancestor_Filename);
      end if;
      if Desc.Builtin_Name /= null then
         Free (Desc.Builtin_Name);
      end if;
   end Free;

   --------------------------
   -- Builtin_Type_To_Kind --
   --------------------------

   procedure Builtin_Type_To_Kind
     (Type_Name : in String;
      Desc      : out CType_Description;
      Success   : out Boolean) is
   begin
      Desc.Parent_Point    := Invalid_Point;
      Desc.Parent_Filename := null;
      if Type_Name = "char"          or Type_Name = "signed char"
         or Type_Name = "int"        or Type_Name = "signed int"
         or Type_Name = "long"       or Type_Name = "signed long"
         or Type_Name = "long long"  or Type_Name = "signed long long"
         or Type_Name = "short"      or Type_Name = "signed short"
      then
         Desc.Kind := Signed_Integer_Type;
         Desc.Builtin_Name := new String' (Type_Name);
         Success := True;
      elsif Type_Name = "unsigned char"
         or Type_Name = "unsigned int"
         or Type_Name = "unsigned long"
         or Type_Name = "unsigned long long"
         or Type_Name = "unsigned short"
      then
         Desc.Kind         := Modular_Integer_Type;
         Desc.Builtin_Name := new String' (Type_Name);
         Success           := True;
      else
         Success := False;
      end if;
   end Builtin_Type_To_Kind;

   -----------------------
   -- Type_Name_To_Kind --
   -----------------------

   procedure Type_Name_To_Kind
     (Type_Name         : in String;
      SN_Table          : in SN_Table_Array;
      Module_Typedefs   : in Module_Typedefs_List;
      Desc              : out CType_Description;
      Success           : out Boolean;
      Symbol            : Symbol_Type := Undef;
      FU_Tab            : FU_Table := Invalid_FU_Table;
      CL_Tab            : CL_Table := Invalid_CL_Table)
   is
      Matches      : Match_Array (0 .. 1);
      Volatile_Str : constant String := "volatile ";
      Const_Str    : constant String := "const ";
   begin
      Success             := False;
      Desc.Is_Template    := False;

      --  check for leading volatile/const modifier
      if Type_Name'Length > Volatile_Str'Length
        and then Type_Name (Type_Name'First ..
                     Type_Name'First + Volatile_Str'Length - 1)
                     = Volatile_Str
      then -- volatile modifier
         Type_Name_To_Kind
           (Type_Name
              (Type_Name'First + Volatile_Str'Length .. Type_Name'Last),
            SN_Table,
            Module_Typedefs,
            Desc,
            Success);
         Desc.Is_Volatile := True;
         return;
      end if;

      if Type_Name'Length > Const_Str'Length
         and then Type_Name (Type_Name'First ..
                     Type_Name'First + Const_Str'Length - 1)
                     = Const_Str
      then -- const modifier
         Type_Name_To_Kind
           (Type_Name
              (Type_Name'First + Const_Str'Length .. Type_Name'Last),
            SN_Table,
            Module_Typedefs,
            Desc,
            Success);
         Desc.Is_Const := True;
         return;
      end if;

      --  first try builtin type
      Builtin_Type_To_Kind (Type_Name, Desc, Success);
      if Success then
         if Desc.Ancestor_Point = Invalid_Point then -- was not set yet
            Desc.Ancestor_Point := Predefined_Point;
         end if;
         return;
      end if;

      if Type_Name (Type_Name'Last) = '*'
         or Type_Name (Type_Name'Last) = '&' then
         Success      := True;
         Desc.Kind    := Access_Type;
         return;
      end if;

      if Type_Name (Type_Name'Last) = ')' then
         --  function pointer?
         Match (Function_Type_Pat, Type_Name, Matches);
         if Matches (0) = No_Match then
            Success := False;
            return;
         end if;
         Type_Name_To_Kind (
            Type_Name (Matches (1).First ..  Matches (1).Last),
            SN_Table,
            Module_Typedefs,
            Desc,
            Success);
         return;
      end if;

      if Type_Name (Type_Name'Last) = ']' then
         --  array
         Success      := True;
         Desc.Kind    := Array_Type;
         return;
      end if;

      --  look in typedefs
      Find_Original_Type
        (Type_Name,
         SN_Table,
         Module_Typedefs,
         Desc,
         Success);

      if Success then -- original type found
         return;
      end if;

      --  look in classes
      if Is_Open (SN_Table (CL)) then
         declare
            Class_Def  : CL_Table;
         begin
            Find_Class (Type_Name, SN_Table, Desc, Class_Def, Success);
            if Success then
               Free (Class_Def);
               return;
            end if;
         end;
      end if;

      --  look in unions
      if Is_Open (SN_Table (UN)) then
         declare
            Union_Def  : UN_Table;
         begin
            Find_Union (Type_Name, SN_Table, Desc, Union_Def, Success);
            if Success then
               Free (Union_Def);
               return;
            end if;
         end;
      end if;

      --  look in enums
      if Is_Open (SN_Table (E)) then
         declare
            Enum_Def : E_Table;
         begin
            Find_Enum (Type_Name, SN_Table, Desc, Enum_Def, Success);
            if Success then
               Free (Enum_Def);
               return;
            end if;
         end;
      end if;

      --  try template arguments
      if (Symbol /= Undef) and (Symbol /= CL) and (Symbol /= UN) then
         Find_Template_Argument
           (Type_Name,
            SN_Table,
            Desc,
            Symbol,
            FU_Tab.Buffer (FU_Tab.Name.First .. FU_Tab.Name.Last),
            FU_Tab.Buffer (FU_Tab.File_Name.First .. FU_Tab.File_Name.Last),
            FU_Tab.Buffer (FU_Tab.Template_Parameters.First ..
                           FU_Tab.Template_Parameters.Last),
            FU_Tab.Buffer (FU_Tab.Class.First .. FU_Tab.Class.Last),
            Success);
         if Success then
            return;
         end if;
      end if;

      --  if this is a method or a class we should try class template arguments
      --  as well
      if (Symbol /= Undef) and (Symbol /= FD) and (Symbol /= FU) then
         Find_Template_Argument
           (Type_Name,
            SN_Table,
            Desc,
            Symbol,
            CL_Tab.Buffer (CL_Tab.Name.First .. CL_Tab.Name.Last),
            CL_Tab.Buffer (CL_Tab.File_Name.First .. CL_Tab.File_Name.Last),
            CL_Tab.Buffer (CL_Tab.Template_Parameters.First ..
                           CL_Tab.Template_Parameters.Last),
            "",
            Success);
         if Success then
            return;
         end if;
      end if;


      --  when everything else failed
      Success := False;
   end Type_Name_To_Kind;

   ------------------------
   -- Find_Original_Type --
   ------------------------

   procedure Find_Original_Type
     (Type_Name         : in String;
      SN_Table          : in SN_Table_Array;
      Module_Typedefs   : in Module_Typedefs_List;
      Desc              : out CType_Description;
      Success           : out Boolean)
   is
      Typedef   : T_Table;
      HTTypedef : Typedef_Entry;
      Key       : String_Access;
      Seek_Key  : String_Access;
      Enclosed_Class  : CL_Table := Invalid_CL_Table;
      Enclosed_Symbol : Symbol_Type := Undef;
   begin
      Success := False;

      if not Is_Open (SN_Table (T)) then
         --  typedef table does not exist
         return;
      end if;

      Typedef   := Find (SN_Table (T), Type_Name);

      Key := new String'(Type_Name);
      Set (Module_Typedefs.all, Key, (Key, Incomplete));
      --  add this type as an unidentified one

      --  lookup left side of the typedef in our type
      --  hash table
      Seek_Key  := new String'
         (Typedef.Buffer (Typedef.Original.First .. Typedef.Original.Last));
      HTTypedef := Get (Module_Typedefs.all, Seek_Key);
      Free (Seek_Key);

      if Desc.Is_Typedef = True
         and then Desc.Ancestor_Point = Invalid_Point
      then -- was not set yet
         Desc.Ancestor_Point    := Typedef.Start_Position;
         Desc.Ancestor_Filename := new String' (Typedef.Buffer (
                       Typedef.File_Name.First .. Typedef.File_Name.Last));
      end if;

      Desc.Is_Typedef := True;

      if HTTypedef.State = Incomplete then -- loop detected
         Desc.Kind := Unresolved_Entity;
         if Desc.Parent_Point = Invalid_Point then
            Desc.Parent_Point    := Typedef.Start_Position;
            Desc.Parent_Filename := new String' (Typedef.Buffer (
                       Typedef.File_Name.First .. Typedef.File_Name.Last));
         end if;
         Success   := True;
         Free (Typedef);
         return;
      end if;

      --  load enclosed class/union (if exists)
      if Typedef.Class_Name /= Empty_Segment then
         declare
            Success : Boolean := False;
            Desc    : CType_Description;
         begin
            Find_Class
              (Type_Name => Typedef.Buffer
                 (Typedef.Class_Name.First .. Typedef.Class_Name.Last),
               SN_Table  => SN_Table,
               Desc      => Desc,
               Class_Def => Enclosed_Class,
               Success   => Success);
            if Success then
               Enclosed_Symbol := CL;
            else
               Find_Union
                 (Type_Name => Typedef.Buffer
                    (Typedef.Class_Name.First .. Typedef.Class_Name.Last),
                  SN_Table  => SN_Table,
                  Desc      => Desc,
                  Union_Def => Enclosed_Class,
                  Success   => Success);
               if Success then
                  Enclosed_Symbol := UN;
               end if;
            end if;
         end;
      end if;

      Type_Name_To_Kind
        (Type_Name       => Typedef.Buffer (
           Typedef.Original.First .. Typedef.Original.Last),
         SN_Table        => SN_Table,
         Module_Typedefs => Module_Typedefs,
         Desc            => Desc,
         Success         => Success,
         Symbol          => Enclosed_Symbol,
         CL_Tab          => Enclosed_Class);

      Free (Enclosed_Class);

      if Success then
         --  parent type found (E_Kind is resolved)
         Desc.Parent_Point    := Typedef.Start_Position;
         Desc.Parent_Filename := new String'(Typedef.Buffer (
                    Typedef.File_Name.First .. Typedef.File_Name.Last));
         Free (Typedef);
         Success := True;
         Set (Module_Typedefs.all, Key, (Key, Complete));
         return;
      end if;

      --  original type not found, but typedef clause present
      Desc.Kind := Unresolved_Entity;
      Success := True;

      Free (Typedef);

   exception
      when  DB_Error |   -- non-existent table
            Not_Found => -- missed, fall thru'
         Success := False;
   end Find_Original_Type;

   ----------------
   -- Find_Class --
   ----------------

   procedure Find_Class
     (Type_Name : in String;
      SN_Table  : in SN_Table_Array;
      Desc      : in out CType_Description;
      Class_Def : out CL_Table;
      Success   : out Boolean)
   is
      Matches      : Match_Array (0 .. 1);
   begin
      Success := False;
      Match (Template_Type_Pat, Type_Name, Matches);
      if Matches (0) /= No_Match then
         Class_Def := Find (SN_Table (CL), Type_Name
            (Matches (1).First .. Matches (1).Last));
         Desc.Is_Template := True;
      else
         Class_Def := Find (SN_Table (CL), Type_Name);
      end if;

      Desc.Parent_Point    := Class_Def.Start_Position;
      Desc.Parent_Filename := new String' (Class_Def.Buffer (
                    Class_Def.File_Name.First .. Class_Def.File_Name.Last));

      if Desc.Ancestor_Point = Invalid_Point then -- was not set yet
         Desc.Ancestor_Point    := Class_Def.Start_Position;
         Desc.Ancestor_Filename := new String' (Class_Def.Buffer (
                       Class_Def.File_Name.First .. Class_Def.File_Name.Last));
      end if;

      if Is_Template (Class_Def) then
         Desc.Is_Template := True;
      end if;

      if Desc.Is_Template then
         Desc.Kind := Generic_Class;
      else
         Desc.Kind := Record_Type;
      end if;

      Success := True;

   exception
      when  DB_Error |   -- non-existent table
            Not_Found => -- missed, fall thru'
         Success := False;
   end Find_Class;

   ----------------
   -- Find_Union --
   ----------------

   procedure Find_Union
     (Type_Name : in String;
      SN_Table  : in SN_Table_Array;
      Desc      : in out CType_Description;
      Union_Def : out UN_Table;
      Success   : out Boolean)
   is
      Matches      : Match_Array (0 .. 1);
   begin
      Success := False;
      Match (Template_Type_Pat, Type_Name, Matches);
      if Matches (0) /= No_Match then
         Union_Def := Find (SN_Table (UN), Type_Name
            (Matches (1).First .. Matches (1).Last));
         Desc.Is_Template := True;
      else
         Union_Def := Find (SN_Table (UN), Type_Name);
      end if;

      Desc.Parent_Point    := Union_Def.Start_Position;
      Desc.Parent_Filename := new String' (Union_Def.Buffer (
                    Union_Def.File_Name.First .. Union_Def.File_Name.Last));

      if Desc.Ancestor_Point = Invalid_Point then -- was not set yet
         Desc.Ancestor_Point    := Union_Def.Start_Position;
         Desc.Ancestor_Filename := new String' (Union_Def.Buffer (
                       Union_Def.File_Name.First .. Union_Def.File_Name.Last));
      end if;

      if (Union_Def.Attributes and SN_TEMPLATE) /= 0 then
         Desc.Is_Template := True;
      end if;

      if Desc.Is_Template then
         Desc.Kind := Generic_Class;
      else
         Desc.Kind := Record_Type;
      end if;

      Success := True;
   exception
      when  DB_Error |   -- non-existent table
            Not_Found => -- missed, fall thru'
         Success := False;
   end Find_Union;

   ---------------
   -- Find_Enum --
   ---------------

   procedure Find_Enum
     (Type_Name : in String;
      SN_Table  : in SN_Table_Array;
      Desc      : in out CType_Description;
      Enum_Def  : out E_Table;
      Success   : out Boolean)
   is
      Matches      : Match_Array (0 .. 1);
   begin
      Success := False;
      Match (Template_Type_Pat, Type_Name, Matches);
      if Matches (0) /= No_Match then
         Enum_Def := Find (SN_Table (E), Type_Name
            (Matches (1).First .. Matches (1).Last));
         Desc.Is_Template := True;
      else
         Enum_Def := Find (SN_Table (E), Type_Name);
      end if;

      Desc.Parent_Point    := Enum_Def.Start_Position;
      Desc.Parent_Filename := new String'
        (Enum_Def.Buffer
          (Enum_Def.File_Name.First .. Enum_Def.File_Name.Last));

      if Desc.Ancestor_Point = Invalid_Point then -- was not set yet
         Desc.Ancestor_Point    := Enum_Def.Start_Position;
         Desc.Ancestor_Filename := new String'
           (Enum_Def.Buffer
             (Enum_Def.File_Name.First .. Enum_Def.File_Name.Last));
      end if;

      Desc.Kind := Enumeration_Type;
      Success := True;
   exception
      when  DB_Error |   -- non-existent table
            Not_Found => -- missed, fall thru'
         Success := False;
   end Find_Enum;

   ----------------------------
   -- Find_Template_Argument --
   ----------------------------

   procedure Find_Template_Argument
     (Type_Name       : String;
      SN_Table        : SN_Table_Array;
      Desc            : in out CType_Description;
      Symbol          : Symbol_Type;
      Scope           : String;
      File_Name       : String;
      Template_Args   : String;
      Class_Name      : String;
      Success         : out Boolean)
   is
      pragma Unreferenced (Symbol);
      Arg             : TA_Table;
      P               : Pair_Ptr;
   begin
      Success := False;
      if not Is_Open (SN_Table (TA)) then
         return;
      end if;

      Set_Cursor
        (SN_Table (TA),
         Position    => By_Key,
         Key         => Scope & Field_Sep & Type_Name & Field_Sep,
         Exact_Match => False);

      loop
         P := Get_Pair (SN_Table (TA), Next_By_Key);
         exit when P = null;
         Arg := Parse_Pair (P.all);
         Free (P);

         if File_Name = Arg.Buffer (Arg.File_Name.First .. Arg.File_Name.Last)
            and Template_Args
               = Arg.Buffer (Arg.Template_Parameters.First ..
                  Arg.Template_Parameters.Last)
            and ((Arg.Buffer (Arg.Class_Name.First .. Arg.Class_Name.Last)
               = Class_Name)
               or ((Arg.Class_Name = Empty_Segment) and Class_Name = "#"))
            and Arg.Attributes /= SN_TA_VALUE
         then
            Desc.Is_Template     := Arg.Attributes = SN_TA_TEMPLATE;
            Desc.Parent_Point    := Arg.Start_Position;
            Desc.Parent_Filename := new String' (File_Name);
            Desc.Kind            := Private_Type;

            if Desc.Ancestor_Point = Invalid_Point then -- was not set yet
               Desc.Ancestor_Point    := Arg.Start_Position;
               Desc.Ancestor_Filename := new String' (File_Name);
            end if;

            Success := True;
            return;
         end if;

         Free (Arg);
      end loop;

      Release_Cursor (SN_Table (TA));
   exception
      when  DB_Error => -- non-existent table
         null;
   end Find_Template_Argument;

   -------------------
   -- Cmp_Arg_Types --
   -------------------

   function Cmp_Arg_Types
     (Buffer_A, Buffer_B     : String_Access;
      Args_A, Args_B         : DB_Structures.Segment_Vector.Node_Access;
      Strict                 : Boolean := False)
      return Boolean
   is
      use DB_Structures.Segment_Vector;
      Ptr_A : Segment_Vector.Node_Access := Args_A;
      Ptr_B : Segment_Vector.Node_Access := Args_B;
   begin
      if (Ptr_A = null and then Ptr_B /= null and then Ptr_B.Next = null
         and then Buffer_B (Ptr_B.Data.First .. Ptr_B.Data.Last) = "void")
         or else (Ptr_B = null and then Ptr_A /= null
         and then Ptr_A.Next = null
         and then Buffer_A (Ptr_A.Data.First .. Ptr_A.Data.Last) = "void")
      then
         return True;
      end if;

      while Ptr_A /= null and then Ptr_B /= null loop
         if not Strict and then
           (Buffer_A (Ptr_A.Data.First .. Ptr_A.Data.Last) = "..."
            or else Buffer_B (Ptr_B.Data.First .. Ptr_B.Data.Last) = "...")
         then
            return True;
         end if;
         if Buffer_A (Ptr_A.Data.First .. Ptr_A.Data.Last)
            /= Buffer_B (Ptr_B.Data.First .. Ptr_B.Data.Last) then
            return False;
         end if;
         Ptr_A := Ptr_A.Next;
         Ptr_B := Ptr_B.Next;
      end loop;

      return Ptr_A = null and then Ptr_B = null;
   end Cmp_Arg_Types;

   --------------------
   -- Cmp_Prototypes --
   --------------------

   function Cmp_Prototypes
     (Buffer_A, Buffer_B     : String_Access;
      Args_A, Args_B         : DB_Structures.Segment_Vector.Node_Access;
      Ret_Type_A, Ret_Type_B : Segment;
      Strict                 : Boolean := False)
      return Boolean
   is
   begin
      return Cmp_Arg_Types (Buffer_A, Buffer_B, Args_A, Args_B, Strict)
         and then Buffer_A (Ret_Type_A.First .. Ret_Type_A.Last)
            = Buffer_B (Ret_Type_B.First .. Ret_Type_B.Last);
   end Cmp_Prototypes;

   ----------
   -- Free --
   ----------

   procedure Free (Module_Typedefs : in out Module_Typedefs_List) is
      procedure Internal_Free is new
        Ada.Unchecked_Deallocation (HTable, Module_Typedefs_List);
   begin
      if Module_Typedefs /= null then
         Free (Module_Typedefs.all);
         Internal_Free (Module_Typedefs);
      end if;
   end Free;

   procedure Init (Module_Typedefs : out Module_Typedefs_List) is
   begin
      Module_Typedefs := new HTable;
   end Init;

   -----------------
   -- Is_Template --
   -----------------

   function Is_Template (The_Class : CL_Table) return Boolean is
   begin
      return (The_Class.Attributes and SN_TEMPLATE) /= 0;
   end Is_Template;

   -----------------
   -- Is_Template --
   -----------------

   function Is_Template (Func : FU_Table) return Boolean is
   begin
      return (Func.Attributes and SN_TEMPLATE) /= 0;
   end Is_Template;

   ----------------------
   -- Plain_Class_Name --
   ----------------------

   function Plain_Class_Name (Type_Name : String) return String is
      Matches : Match_Array (0 .. 1);
   begin
      Match (Template_Type_Pat, Type_Name, Matches);
      if Matches (0) = No_Match then
         return Type_Name;
      else
         return Type_Name (Matches (1).First .. Matches (1).Last);
      end if;
   end Plain_Class_Name;

end Src_Info.Type_Utils;
