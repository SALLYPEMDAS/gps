-----------------------------------------------------------------------
--                   GVD - The GNU Visual Debugger                   --
--                                                                   --
--                      Copyright (C) 2000-2001                      --
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

with GNAT.Regpat;
with Basic_Types;
with Interfaces.C.Strings;

package Language is

   type Language_Root is abstract tagged private;
   type Language_Access is access all Language_Root'Class;

   Unexpected_Type : exception;

   procedure Free (Lang : in out Language_Access);
   --  Free the memory pointed to by Lang and set it to null.

   ------------------------
   -- Types manipulation --
   ------------------------
   --  The following functions are provided to manipulate types and variables
   --  for each language.

   function Is_Simple_Type
     (Lang : access Language_Root; Str : String) return Boolean is abstract;
   --  Return True if Str is a simple type, like integer, ...
   --  These are the types that don't need information from the debugger to
   --  be known, ie we can save a call to the debugger when parsing the value
   --  of a variable.

   --------------------------------
   -- Highlighting in the editor --
   --------------------------------

   type Language_Entity is
     (Normal_Text,
      Identifier_Text,
      Keyword_Text,
      Comment_Text,
      Character_Text,
      String_Text);
   --  The entities found in a language, and that can have a different scheme
   --  for colors highlighting.

   subtype Standout_Language_Entity is Language_Entity
     range Keyword_Text .. String_Text;
   --  All the entities that have a special significance. Used for syntax
   --  highlighting for example.

   procedure Looking_At
     (Lang      : access Language_Root;
      Buffer    : String;
      Entity    : out Language_Entity;
      Next_Char : out Positive);
   --  Should return the type of entity that is present at the first position
   --  in the buffer (ie starting at Buffer'First).
   --  Next_Char should be set to the index of the first character after the
   --  entity.

   function Keywords
     (Lang : access Language_Root)
      return GNAT.Regpat.Pattern_Matcher is abstract;
   --  Return a regular expression that matches the keywords for the current
   --  language.

   ----------------------------
   -- Tooltips in the editor --
   ----------------------------

   function Can_Tooltip_On_Entity
     (Lang : access Language_Root;
      Entity : String) return Boolean;
   --  Return True if we should display a tooltip for the Entity.
   --  Note that Entity is analyzed in the current context. This is used at
   --  least for the gdb Ada mode, since we don't want to evaluate subprograms
   --  when the type of tooltips in Simple.
   --  By default, this simply returns True.

   ------------------------
   -- Naming conventions --
   ------------------------

   function Dereference_Name
     (Lang : access Language_Root;
      Name : String) return String is abstract;
   --  Return the name to use to dereference Name (ie in Ada "Name.all", in
   --  C "*Name", ...). Note that Name can be a composite name (Name.Field),
   --  and thus might have to be protected with parentheses.

   function Array_Item_Name
     (Lang  : access Language_Root;
      Name  : String;
      Index : String) return String is abstract;
   --  Return the name to use to access a specific element of an array.
   --  Index is a comma-separated list of the indexes for all the dimensions,
   --  as in "1,2".

   function Record_Field_Name
     (Lang  : access Language_Root;
      Name  : String;
      Field : String) return String is abstract;
   --  Return the name to use for a specific field of a record.

   ------------------
   -- The explorer --
   ------------------
   --  These functions are provided as a support for the source code explorer.

   type Category_Index is new Positive;
   type Make_Entry_Func is access function
     (Str      : String;
      Matched  : GNAT.Regpat.Match_Array;
      Category : access Category_Index) return String;
   --  Function that builds the string to be inserted in the tree.
   --  It is possible for the function to change the category used for the
   --  item (for instance when subprograms declarations and bodies have
   --  basically the same aspect, it is possible to use only one regular
   --  expression and distinguish only by testing for some special substring
   --  in this function.

   type Pattern_Matcher_Access is access all GNAT.Regpat.Pattern_Matcher;

   type Explorer_Category is record
      Name           : Basic_Types.String_Access;
      Regexp         : Pattern_Matcher_Access;
      Position_Index : Natural;
      Icon           : Basic_Types.Pixmap_Access;
      Make_Entry     : Make_Entry_Func;
   end record;
   --  Definition for a category (ie one of the subtrees of the explorer).
   --  Icon is the icon to use for items in this category.
   --  Regexp is the general regular expression to use for entries in this
   --  category, while Make_Entry is the function that will return the
   --  actual string to be displayed in the explorer.
   --  Position_Index is the index of the parenthesis-pair that the entity
   --  name starts at. When the user clicks on this item in the explorer,
   --  the cursor will be moved to that location in the editor.
   --
   --  If Make_Entry is null, then the regexp is never tested against the
   --  source code. You can only add items to this category by modifying the
   --  Category parameter of another category's Make_Entry (see
   --  language-ada.adb).

   type Explorer_Categories is
     array (Category_Index range <>) of Explorer_Category;
   --  A list of categories. Each category is assigned an internal number which
   --  is the index in this table, and is passed to each Make_Entry_Func
   --  functions.

   function Explorer_Regexps
     (Lang : access Language_Root) return Explorer_Categories;
   --  Return the list of categories for a given language.
   --  By default, no category is defined, and thus the explorer is empty.

   function Is_System_File
     (Lang      : access Language_Root;
      File_Name : String) return Boolean;
   --  Return True if File_Name is the name of a system file (standard include
   --  files in C or run-time file in Ada). These files are displayed
   --  separately in the explorer.

   ------------------------
   -- Language Detection --
   ------------------------
   --  The following functions provide a way to convert from file names to
   --  their associated language, based on regular expressions.

   function Get_Language_From_File (File_Name : String) return Language_Access;
   --  Return the language to use for a specific file name.
   --  Note that the language returned is an instance of Language_Ada,
   --  Language_C, or other similar-level objects, and does not know
   --  anything about the debugger.
   --  null is returned if no pattern matched the file name.
   --
   --  The access returned points to a global instance, and should not be
   --  modified directly.

   procedure Add_File_Extension (Language : Language_Access; Pattern : String);
   --  Add a new regexp pattern.
   --  Any file whose name matches Pattern will be associated with Language.
   --  No copy of Language is made.
   --  Pattern follows regular expressions as defined in GNAT.Regpat and do not
   --  have to match the entire file, e.g "\.ads$" to match a file ending with
   --  ".ads".
   --  Thanks to this function, this package doesn't have to know anything
   --  about specific languages.

   procedure Add_File_Extensions (Lang : Language_Access; Extensions : String);
   --  Add all the extensions contained in Str (separated by semicolons)
   --  for the language Lang.
   --  Extensions do not contain any regexp and are of the form:
   --  .ads;.adb

   procedure Reset_File_Extensions;
   --  Remove all registered file extensions.

   ----------------------
   -- Language Context --
   ----------------------

   type Language_Context
     (Comment_Start_Length          : Natural;
      Comment_End_Length            : Natural;
      New_Line_Comment_Start_Length : Natural) is
   --  Set any of the length to 0 if there is no such comment
   record
      Comment_Start : String (1 .. Comment_Start_Length);
      --  How comments start for this language. This is for comments that
      --  do not end on Newline, but with Comment_End.

      Comment_End : String (1 .. Comment_End_Length);
      --  How comments end for this language

      New_Line_Comment_Start : String (1 .. New_Line_Comment_Start_Length);
      --  How comments start. These comments end on the next newline character.

      String_Delimiter : Character;
      --  How strings start and end

      Quote_Character : Character;
      --  The character used to quote (protect) the following one. If this is
      --  set to ASCII.NUL, then there is no such character in the
      --  language. For instance, it should be set to \ for C.

      Constant_Character : Character;
      --  The character that starts and ends constant characters
   end record;
   --  This record describes the syntax of the language (for color
   --  highlighting purposes). All the fields in this record are language
   --  specific, and do not depend on the debugger used.

   function Get_Language_Context
     (Lang : access Language_Root) return Language_Context is abstract;
   --  Return the context to use for a specific language

   ----------------------
   -- Source Analyzing --
   ----------------------

   type Casing_Type is (Unchanged, Upper, Lower, Mixed);
   --  Casing used for identifiers and reserved words.
   --  Only relevant for case insensitive languages.

   type Source_Location is record
      Line   : Natural := 0;
      --  Line number for this entity

      Column : Natural := 0;
      --  Column number for this entity

      Index  : Natural := 0;
      --  Index in the buffer for this entity
   end record;

   type Indent_Parameters is record
      Indent_Level    : Natural;
      Indent_Continue : Natural;
      Indent_Decl     : Natural;
      Indent_Return   : Natural;
      Indent_Renames  : Natural;
      Indent_With     : Natural;
      Indent_Use      : Natural;
      Indent_Record   : Natural;
   end record;
   --  Define all parameters to indent a source code.
   --  Note that some of these parameters will be ignored, depending on the
   --  actual language.
   --
   --  Indent_Level    number of spaces when indenting a block.
   --  Indent_Continue number of spaces for a continuation line.
   --  Indent_Decl     number of extra spaces for variables declaration.
   --  Indent_Return   number of extra spaces for the return line in a
   --                  function declaration.
   --  Indent_Renames  number of extra spaces for the renames line in a
   --                  function declaration.
   --  Indent_With     number of spaces when indenting a with clause.
   --  Indent_Use      number of spaces when indenting a use clause.
   --  Indent_Record   number of extra spaces for a record declaration
   --                  when the record keyword is on its own line.

   Default_Indent_Parameters : constant Indent_Parameters :=
     (Indent_Level    => 3,
      Indent_Continue => 2,
      Indent_Decl     => 0,
      Indent_Return   => 2,
      Indent_Renames  => 2,
      Indent_With     => 5,
      Indent_Use      => 4,
      Indent_Record   => 3);

   type Language_Category is
     (Cat_Unknown,

      ------------------------
      -- Enclosing Entities --
      ------------------------

      Cat_Package,
      Cat_Namespace,
      Cat_Task,        --  Subprogram
      Cat_Procedure,   --  Subprogram, Subprogram_Explorer
      Cat_Function,    --  Subprogram, Subprogram_Explorer
      Cat_Method,      --  Subprogram, Subprogram_Explorer
      Cat_Constructor, --  Subprogram, Subprogram_Explorer
      Cat_Destructor,  --  Subprogram, Subprogram_Explorer
      Cat_Protected,   --  Subprogram
      Cat_Entry,       --  Subprogram

      ----------------
      -- Data/Types --
      ----------------

      Cat_Class,
      Cat_Structure,
      Cat_Type,
      Cat_Subtype,
      Cat_Variable,
      Cat_Local_Variable,
      Cat_Representation_Clause,

      ----------------
      -- Dependency --
      ----------------

      Cat_With,
      Cat_Use,
      Cat_Include,

      ----------------
      -- Constructs --
      ----------------

      Cat_Loop_Statement,
      Cat_If_Statement,
      Cat_Case_Statement,
      Cat_Select_Statement,
      Cat_Accept_Statement,
      Cat_Declare_Block,
      Cat_Simple_Block,
      Cat_Exception_Handler);

   subtype Enclosing_Entity_Category is Language_Category
     range Cat_Package .. Cat_Entry;

   subtype Subprogram_Category is Enclosing_Entity_Category
     range Cat_Task .. Cat_Entry;

   subtype Subprogram_Explorer_Category is Subprogram_Category
     range Cat_Procedure .. Cat_Destructor;
   --  Subprograms, as displayed in the explorer

   subtype Data_Type_Category is Language_Category
     range Cat_Class .. Cat_Variable;

   subtype Type_Category is Data_Type_Category
     range Cat_Class .. Cat_Subtype;

   subtype Dependency_Category is Language_Category
     range Cat_With .. Cat_Include;

   subtype Construct_Category is Language_Category
     range Cat_Loop_Statement .. Cat_Exception_Handler;

   type Construct_Information;
   type Construct_Access is access Construct_Information;

   type Construct_Information is record
      Category        : Language_Category;
      --  Define the kind of construct

      Name            : Basic_Types.String_Access;
      --  Name of the enclosing token. Null if not relevant for Token.

      Profile         : Basic_Types.String_Access;
      --  Subprogram profile, if Category is in Subprogram_Category.
      --  Note that even for Subprogram_Category, Profile can be null if the
      --  subprogram does not have any parameter.

      Sloc_Start      : Source_Location;
      --  Location of beginning of the construct

      Sloc_End        : Source_Location;
      --  Location of end of the construct

      Is_Declaration  : Boolean;
      --  Is this a declaration (e.g function specification) ?

      Prev, Next      : Construct_Access;
      --  Links to the previous and the next construct info
   end record;
   --  Information needed to define a language construct (e.g procedure,
   --  loop statement, ...).

   type Construct_List is record
      First, Current, Last : Construct_Access;
   end record;

   procedure Free (List : in out Construct_List);
   --  Free the contents of List.

   procedure Format_Source
     (Lang             : access Language_Root;
      Buffer           : String;
      Indent_Params    : Indent_Parameters := Default_Indent_Parameters;
      Reserved_Casing  : Casing_Type       := Lower;
      Ident_Casing     : Casing_Type       := Mixed;
      Format_Operators : Boolean           := True);
   --  Format Buffer and output the result on standard output.
   --  Reserved_Casing specifies the casing for reserved words.
   --  Ident_Casing specifies the casing for identifiers.
   --  If Format_Operators is True, spaces are added when appropriate around
   --  operators (e.g a space after commas, before left paren, etc...).

   procedure Parse_Constructs
     (Lang            : access Language_Root;
      Buffer          : Interfaces.C.Strings.chars_ptr;
      Buffer_Length   : Natural;
      Result          : out Construct_List;
      Indent          : out Natural;
      Next_Indent     : out Natural;
      Indent_Params   : Indent_Parameters := Default_Indent_Parameters);
   --  Parse the constructs contained in Buffer and store all the language
   --  constructs with their source location in Result.
   --  As a bonus (since it is computed anyway), store the current and
   --  next indentation levels.

   procedure Next_Indentation
     (Lang          : access Language_Root;
      Buffer        : Interfaces.C.Strings.chars_ptr;
      Buffer_Length : Natural;
      Indent        : out Natural;
      Next_Indent   : out Natural;
      Indent_Params : Indent_Parameters := Default_Indent_Parameters);
   --  Given a Buffer, return the indentation level for the last character
   --  in the buffer and for the next line.

   type Entity_Callback is access function
     (Entity     : Language_Entity;
      Sloc_Start : Source_Location;
      Sloc_End   : Source_Location) return Boolean;
   --  Callback during parsing of entities.
   --  If Callback returns True, the parsing should be stopped.

   procedure Parse_Entities
     (Lang          : access Language_Root;
      Buffer        : Interfaces.C.Strings.chars_ptr;
      Buffer_Length : Natural;
      Callback      : Entity_Callback);
   --  Parse entities (as defined by Source_Entity_Kind) contained in buffer.
   --  For each match, call Callback. Stops at the end of Buffer or when
   --  callback returns True.

private
   type Language_Root is abstract tagged null record;
end Language;
