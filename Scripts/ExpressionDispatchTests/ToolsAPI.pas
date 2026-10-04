unit ToolsAPI;
interface
type
  TOTAEditPos = packed record Col: SmallInt; Line: Longint; end;
  TOTACharPos = packed record CharIndex: SmallInt; Line: Longint; end;
  TOTABlockType = (btInclusive, btLine, btColumn, btNonInclusive, btUnknown);
implementation
end.
