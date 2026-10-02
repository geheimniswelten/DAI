unit ForeignVirtualTrees;

interface

uses
  Vcl.Controls;

type
  // Same class names from an unrelated module must fail the origin guard.
  TBaseVirtualTree = class(TCustomControl);
  TCustomVirtualStringTree = class(TBaseVirtualTree);

implementation

end.
