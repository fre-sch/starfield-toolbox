{

}
unit BlenderJSONExport;

const
  CELL_PERSISTENT_CHILDREN = 8;
  CELL_TEMPORARY_CHILDREN = 9;
  START_SIGNATURES = 'CELL,REFR,MSTT,STAT,STMP';

var
  global_target_path: string;


procedure ProcessMeta(element: IInterface; result_json: TJsonObject);
begin
  result_json.O['Meta'].S['FormID'] := IntToHex64(FixedFormID(element), 8);
  result_json.O['Meta'].S['EDID'] := EditorID(element);
  result_json.O['Meta'].S['Signature'] := Signature(element);
  // these are informative only
  result_json.O['Meta'].S['FileName'] := GetFileName(GetFile(element));
  result_json.O['Meta'].S['Name'] := Name(element);
end;


procedure ProcessXYZ(element: IInterface; result_json: TJsonObject);
begin
  result_json.S['X'] := GetElementEditValues(element, 'X');
  result_json.S['Y'] := GetElementEditValues(element, 'Y');
  result_json.S['Z'] := GetElementEditValues(element, 'Z');
end;


procedure ProcessOrientation(
  offset_element, rotation_element: IInterface;
  result_json: TJsonObject);
begin
  ProcessXYZ(offset_element, result_json.O['Offset']);
  ProcessXYZ(rotation_element, result_json.O['Rotation']);
end;


procedure ProcessSTMPNode(node_element: IInterface; result_json: TJsonObject);
var
  node_id: string;
  node_name: string;
begin
  node_id := GetElementEditValues(node_element, 'Node ID');
  node_name := GetElementEditValues(node_element, 'Node');
  result_json.O['Meta'].S['Signature'] := 'STMP.Node';
  result_json.O['Meta'].S['Name'] := node_id + ':' + node_name;
  result_json.S['Node ID'] := node_id;
  result_json.S['Node'] := node_name;
  ProcessOrientation(
    ElementByPath(node_element, 'Orientation\Offset'),
    ElementByPath(node_element, 'Orientation\Rotation'),
    result_json.O['Orientation']);
end;


procedure ProcessSTMP(stmp_record: IInterface; result_json: TJsonObject);
var
  nodes_element: IInterface;
  node_element: IInterface;
  i: Integer;
begin
  ProcessMeta(stmp_record, result_json);

  nodes_element := ElementBySignature(stmp_record, 'ENAM');
  for i := 0 to Pred(ElementCount(nodes_element)) do begin
    node_element := ElementByIndex(nodes_element, i);
    AddMessage('--- node signature: ' + Signature(node_element));
    ProcessSTMPNode(node_element, result_json.A['ENAM'].AddObject);
  end;
end;


procedure ProcessMSTTorSTAT(subrecord: IInterface; result_json: TJsonObject);
var
  stmp_record: IInterface;
begin
  ProcessMeta(subrecord, result_json);

  result_json.S['MODL'] := GetElementEditValues(subrecord, 'Model\MODL');
  ProcessXYZ(ElementByPath(subrecord, 'OBND\Min'), result_json.O['OBND'].O['Min']);
  ProcessXYZ(ElementByPath(subrecord, 'OBND\Max'), result_json.O['OBND'].O['Max']);

  stmp_record := LinksTo(ElementBySignature(subrecord, 'SNTP'));
  if not Assigned(stmp_record) then Exit;
  ProcessSTMP(stmp_record, result_json.O['SNTP']);
end;

procedure ProcessRefrData(refr_record: IInterface; result_json: TJsonObject);
var
  data_element: IInterface;
  xscal_element: IInterface;
begin
  data_element := ElementBySignature(refr_record, 'DATA');
  if not Assigned(data_element) then Exit;
  ProcessOrientation(
    ElementByPath(data_element, 'Position'),
    ElementByPath(data_element, 'Rotation'),
    result_json.O['DATA']
  );
  xscal_element := ElementBySignature(refr_record, 'XSCL');
  if Assigned(xscal_element) then
    result_json.S['XSCL'] = GetEditValue(refr_record);
end;


procedure ProcessCellRefs(cell_group_element: IInterface; result_json: TJsonArray);
var
  i: integer;
  refr_element: IInterface;
  linked_record: IInterface;
  item_json: TJsonObject;
begin
  for i := 0 to Pred(ElementCount(cell_group_element)) do begin
    refr_element := ElementByIndex(cell_group_element, i);
    linked_record := LinksTo(ElementBySignature(refr_element, 'NAME'));
    item_json := result_json.AddObject;
    ProcessMeta(refr_element, item_json);
    ProcessRefrData(refr_element, item_json);
    if Assigned(linked_record) then
    begin
      if Pos(Signature(linked_record), 'MSTT,STAT') > 0 then
        ProcessMSTTorSTAT(linked_record, item_json.O['NAME'])
      else
          ProcessMeta(linked_record, item_json.O['NAME']);
    end;
  end;
end;


procedure ProcessCell(cell_subrecord: IInterface; result_json: TJsonObject);
var
  cell_child_group_children: IInterface;
  cell_child_group: IInterface;
begin
  ProcessMeta(cell_subrecord, result_json);

  cell_child_group := ChildGroup(cell_subrecord);
  cell_child_group_children := FindChildGroup(
    cell_child_group, CELL_TEMPORARY_CHILDREN, cell_subrecord);
  ProcessCellRefs(cell_child_group_children, result_json.A['Temporary']);

  cell_child_group_children := FindChildGroup(
    cell_child_group, CELL_PERSISTENT_CHILDREN, cell_subrecord);
  ProcessCellRefs(cell_child_group_children, result_json.A['Persistent']);
end;


function SaveAs(file_name: string): string;
var
  save_dialog: TSaveDialog;
begin
  save_dialog := TSaveDialog.Create(nil);
  try
    save_dialog.Options := save_dialog.Options + [ofOverwritePrompt];
    save_dialog.InitialDir := wbDataPath;
    save_dialog.FileName := ExtractFileName(file_name);
    if save_dialog.Execute then begin
      Result := save_dialog.FileName;
    end;
  finally
    save_dialog.Free;
  end;
end;



function Initialize: integer;
begin
  Result := 0;
  global_target_path :=  ExtractFilePath(SaveAs('tmp.json'));
end;


function Process(element: IInterface): integer;
var
  result_json: TJsonObject;
begin
  Result := 0;
  if Pos(Signature(element), START_SIGNATURES) = 0 then begin
    AddMessage('Got ' + Signature(element) + ', only works with: ' + START_SIGNATURES);
    Result := 1;
    Exit;
  end;

  result_json := TJsonObject.Create;

  if Signature(element) = 'STMP' then
    ProcessSTMP(element, result_json)
  else if Signature(element) = 'MSTT' then
    ProcessMSTTorSTAT(element, result_json)
  else if Signature(element) = 'STAT' then
    ProcessMSTTorSTAT(element, result_json)
  else if Signature(element) = 'CELL' then
    ProcessCell(element, result_json)
  else
  begin
    // selecting a CELL doesn't just call us with the CELL, but also with all children
    AddMessage('skip: ' + FullPath(element));
    Exit;
  end;

  result_json.SaveToFile(
    global_target_path + '\' + EditorID(element) + '.' + IntToHex64(FixedFormID(element), 8) + '.' + Signature(element) + '.json',
    False, TEncoding.UTF8, True);
  result_json.Free;
end;

end.
