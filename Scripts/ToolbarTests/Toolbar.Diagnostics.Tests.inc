procedure TestToolbarLayoutDiagnostics;
var
  LForm: TForm;
  LToolbar: TDiagnosticToolbar;
  LButton: TToolButton;
  LImages: TImageList;
  LBitmap: Vcl.Graphics.TBitmap;
  LResult: TJSONObject;
  LMetadata, LLayout, LNative, LRect: TJSONObject;
  LNativeButton: TTBButton;
  LPayload: string;
  LIndex: Integer;

  procedure Inspect;
  var
    LFound: TJSONObject;
  begin
    FreeAndNil(LResult);
    LResult := TDAIWindowService.IDEWindows(True, 100, 500, 1000);
    LFound := FindVCLName(LResult, LButton.Name);
    Check(Assigned(LFound), 'Toolbar diagnostics find the real graphic button');
    LMetadata := TJSONObject(LFound.GetValue('vcl'));
    Check(Assigned(LMetadata), 'Toolbar diagnostics retain real VCL metadata');
    LLayout := TJSONObject(LMetadata.GetValue('parent_toolbar'));
    Check(Assigned(LLayout), 'Toolbar diagnostics expose the actual parent layout');
    LNative := TJSONObject(LLayout.GetValue('native'));
    Check(Assigned(LNative), 'Native toolbar diagnostics have a bounded result object');
  end;

begin
  LResult := nil;
  LForm := TForm.CreateNew(nil);
  try
    LForm.Name := 'WindowInspectionLayoutForm';
    LToolbar := TDiagnosticToolbar.Create(LForm);
    LToolbar.Name := 'WindowInspectionLayoutToolbar';
    LToolbar.Parent := LForm;
    LToolbar.Align := alNone;
    LToolbar.AutoSize := False;
    LToolbar.Wrapable := False;
    LToolbar.HideClippedButtons := True;
    LToolbar.SetBounds(10, 10, 300, 30);
    LImages := TImageList.Create(LForm);
    LBitmap := Vcl.Graphics.TBitmap.Create;
    try
      LBitmap.SetSize(16, 16);
      LBitmap.Canvas.Brush.Color := clLime;
      LBitmap.Canvas.FillRect(Rect(0, 0, 16, 16));
      LImages.Add(LBitmap, nil);
      LImages.Add(LBitmap, nil);
    finally
      LBitmap.Free;
    end;
    LToolbar.Images := LImages;
    LButton := TToolButton.Create(LForm);
    LButton.Name := 'WindowInspectionLayoutButton';
    LButton.Parent := LToolbar;
    LButton.ImageIndex := 1;
    LButton.Style := tbsDropDown;
    LIndex := LButton.Index;
    Check(SendMessage(LToolbar.Handle, TB_GETBUTTON, WPARAM(LIndex), LPARAM(@LNativeButton)) <> 0,
      'Isolated common control supplies a real native button record');
    Inspect;
    Check(JsonInteger(LMetadata, 'button_index') = LIndex, 'Public VCL button index is reported');
    Check(JsonString(LMetadata, 'visible') = 'true', 'Graphic button remains VCL-visible');
    LRect := TJSONObject(LMetadata.GetValue('bounds'));
    Check(Assigned(LRect), 'Graphic button bounds are reported without a button HWND');
    Check(JsonInteger(LRect, 'left') = LButton.Left, 'Button bounds use its real parent-relative left');
    Check(JsonInteger(LRect, 'right') = LButton.Left + LButton.Width, 'Button bounds retain actual width');
    Check(JsonString(LLayout, 'handle_allocated') = 'true', 'Existing toolbar HWND is acknowledged');
    Check(JsonInteger(LLayout, 'client_width') = LToolbar.ClientWidth, 'Existing toolbar client width agrees with VCL');
    Check(JsonInteger(LLayout, 'client_height') = LToolbar.ClientHeight, 'Existing toolbar client height agrees with VCL');
    Check(JsonString(LLayout, 'auto_size') = 'false', 'Actual toolbar AutoSize is reported');
    Check(JsonString(LLayout, 'wrapable') = 'false', 'Actual toolbar Wrapable is reported');
    Check(JsonString(LLayout, 'hide_clipped_buttons') = 'true', 'Actual HideClippedButtons is reported');
    Check(JsonString(LLayout, 'showing') = 'false', 'An invisible parent form is reflected by toolbar Showing');
    Check(JsonInteger(LLayout, 'images_count') = 2, 'Actual VCL image count is read');
    Check(JsonInteger(LNative, 'images_count') = 2, 'Actual native image-list count is read');
    Check(JsonString(LNative, 'has_image_list') = 'true', 'Existing native image list is reported without its handle');
    Check(JsonInteger(LNative, 'button_count') = 1, 'Actual native toolbar count is reported');
    Check(JsonString(LNative, 'available') = 'true', 'Existing native toolbar record is available');
    Check(JsonString(LNative, 'identity_matches') = 'true', 'Native dwData matches this exact VCL button as a boolean');
    Check(JsonInteger(LNative, 'state') = LNativeButton.fsState, 'Actual native state bits are retained');
    Check(JsonInteger(LNative, 'image_index') = 1, 'Actual native image index is retained');
    Check(JsonString(LNative, 'hidden') = 'false', 'Initially visible native button is not hidden');
    Check(JsonString(LNative, 'clipped') = 'false', 'An ample toolbar does not clip the native button');
    LPayload := LResult.ToJSON;
    Check(not LPayload.Contains(IntToStr(NativeUInt(Pointer(LButton)))), 'Raw dwData pointer is never serialized as a number');
    Check(not LPayload.Contains('dwData'), 'No raw native pointer field is exported');
    LToolbar.SetBounds(10, 10, 5, 30);
    Inspect;
    Check(JsonString(LNative, 'clipped') = 'true', 'Narrow fixed-width toolbar really clips the native item rectangle');
    Check(JsonString(LMetadata, 'visible') = 'true', 'Geometry clipping differs from the unchanged VCL Visible flag');
    Check(SendMessage(LToolbar.Handle, TB_HIDEBUTTON, WPARAM(LNativeButton.idCommand), 1) <> 0,
      'Fixture independently hides the actual native common-control button');
    Inspect;
    Check(JsonString(LNative, 'hidden') = 'true', 'Native TBSTATE_HIDDEN is reported independently from VCL state');
    Check(JsonString(LMetadata, 'visible') = 'true', 'Native hiding does not fabricate a VCL visibility change');
    Check(SendMessage(LToolbar.Handle, TB_DELETEBUTTON, WPARAM(LIndex), 0) <> 0,
      'Fixture independently removes a native button while retaining the VCL control');
    Inspect;
    Check(JsonString(LNative, 'available') = 'false', 'Missing native index is unavailable');
    Check(JsonString(LNative, 'reason') = 'index_outside_native_buttons', 'Index guard explains missing native record');
    Check(JsonInteger(LNative, 'button_count') = 0, 'Native empty count is reported accurately');
    Check(not Assigned(LNative.GetValue('state')), 'Invalid native index never reads a state record');
    LToolbar.DropNativeHandle;
    Check(not LToolbar.HandleAllocated, 'Fixture removes only its disposable toolbar HWND');
    Inspect;
    Check(not LToolbar.HandleAllocated, 'Inspection never recreates a missing toolbar HWND');
    Check(JsonString(LLayout, 'handle_allocated') = 'false', 'Missing parent HWND is reported');
    Check(LLayout.GetValue('client_rect') is TJSONNull, 'Unallocated client rectangle is honest null');
    Check(LLayout.GetValue('client_width') is TJSONNull, 'Unallocated client width is honest null');
    Check(LLayout.GetValue('client_height') is TJSONNull, 'Unallocated client height is honest null');
    Check(JsonString(LNative, 'available') = 'false', 'No native toolbar record is read without a handle');
    Check(JsonString(LNative, 'reason') = 'handle_not_allocated', 'Absent native handle reason is explicit');
    Check(JsonInteger(LLayout, 'images_count') = 2, 'Existing VCL image count remains independently readable');
    Check(not Assigned(LNative.GetValue('button_count')), 'Unallocated native toolbar never fabricates a native count');
  finally
    LResult.Free;
    LForm.Free;
  end;
end;
