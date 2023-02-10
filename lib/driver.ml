open Lexing
open Printf
module E = MenhirLib.ErrorReports
module L = MenhirLib.LexerUtil
module I = UnitActionsParser.MenhirInterpreter

let try_parse lexbuf text =
  match Parser.fmodule Lexer.read lexbuf with
  | ast -> Some ast
  | exception LexerUtil.Error msg ->
      let pos = LexerUtil.format_pos lexbuf in
      Printf.eprintf "Syntax error on %s:\n\n  %s\n" pos msg;
      Printf.eprintf "\n--------------------\n%s\n--------------------\n" text;
      None
  | exception Parser.Error -> None

let env checkpoint =
  match checkpoint with I.HandlingError env -> env | _ -> assert false

let state checkpoint : int =
  match I.top (env checkpoint) with
  | Some (I.Element (s, _, _, _)) -> I.number s
  | None -> 0

let show text positions =
  E.extract text positions |> E.sanitize |> E.compress |> E.shorten 20

let get text checkpoint i =
  match I.get i (env checkpoint) with
  | Some (I.Element (_, _, pos1, pos2)) -> show text (pos1, pos2)
  | None -> "???"

let succeed (fmodule : Ast.fmodule) : (Ast.fmodule, string) result = Ok fmodule

let fail text buffer (checkpoint : Ast.fmodule I.checkpoint) =
  let location = L.range (E.last buffer) in
  let indication = sprintf "Syntax error %s.\n" (E.show (show text) buffer) in
  let message = ParserMessages.message (state checkpoint) in
  let message = E.expand (get text checkpoint) message in
  let err = sprintf "%s%s%s%!" location indication message in
  Error err

let fallback file_name text =
  let lexbuf = L.init file_name (Lexing.from_string text) in
  let supplier = I.lexer_lexbuf_to_supplier Lexer.read lexbuf in
  let buffer, supplier = E.wrap_supplier supplier in
  let checkpoint = UnitActionsParser.Incremental.fmodule lexbuf.lex_curr_p in
  I.loop_handle succeed (fail text buffer) supplier checkpoint

(* Entrypoints *)

let parse_text text =
  let lexbuf = Lexing.from_string text in
  let maybe_fmodule = try_parse lexbuf text in
  match maybe_fmodule with Some fmodule -> Ok fmodule | None -> fallback "<text>" text

let parse_file file_name =
  let text, lexbuf = L.read file_name in
  let maybe_fmodule = try_parse lexbuf text in
  match maybe_fmodule with
  | Some fmodule -> Ok fmodule
  | None -> fallback file_name text
