{
  Import JSON as exported by BlenderJSON-Export.pas and update REFR, MSTT, STAT
  and STMP node position and rotation data.
}
unit BlenderJSONImportUpdate;


const
  CELL_PERSISTENT_CHILDREN = 8;
  CELL_TEMPORARY_CHILDREN = 9;
  IMPORTABLE_SIGNATURES = 'CELL,REFR,MSTT,STMP,STMP.Node';
  EXCLUDE_FILES_MASTERS = 'Starfield.esm,Starfield.exe,BlueprintShips-Starfield.esm,OldMars.esm,Constellation.esm';


function FileByName(name: string): IwbFile;
var
  i: integer;
begin
  Result := nil;
  for i := 0 to Pred(FileCount) do begin
    if SameText(GetFileName(FileByIndex(i)), name) then
    begin
      Result := FileByIndex(i);
      Exit;
    end;
  end;
end;


function RecordByMeta(json_data: TJsonObject): IInterface;
var
  record_file: IwbFile;
begin
  Result := nil;

  if Pos(json_data.O['Meta'].S['FileName'], EXCLUDE_FILES_MASTERS) <> 0 then
    Exit;

  record_file := FileByName(json_data.O['Meta'].S['FileName']);
  if not Assigned(record_file) then
  begin
    AddMessage('file '+ json_data.O['Meta'].S['FileName'] + ' not found for: ' + json_data.O['Meta'].S['FormID']);
    Exit;
  end;

  Result := RecordByFormID(
    record_file,
    StrToInt('$' + json_data.O['Meta'].S['FormID']),
    true
  );
  if not Assigned(Result) then
    AddMessage('    record not found: ' + json_data.O['Meta'].S['FormID'])
  else
    AddMessage('    record found: ' + FullPath(Result));
end;


function ValidateMetaJSON(json_data: TJsonObject; check_signature: string): bool;
var
  meta_signature: string;
begin
  Result := false;

  if not json_data.Contains('Meta') then
  begin
    AddMessage('    Meta object missing');
    Exit;
  end;

  if not json_data.O['Meta'].Contains('FormID') then
  begin
    AddMessage('    Meta.FormID missing');
    Exit;
  end;

  if not json_data.O['Meta'].Contains('Signature') then
  begin
    AddMessage('    Meta.Signature missing');
    Exit;
  end;

  // TODO: not sure how useful this warning really is, when REFR and STMP.Node
  // and maybe others just don't have an EDID, and the script doesn't really do
  // anything with the EDID
  // if not json_data.O['Meta'].Contains('EDID') then
  // begin
  //   AddMessage('    Warning: Meta.EDID missing');
  // end;

  meta_signature := json_data.O['Meta'].S['Signature'];
  if Pos(meta_signature, check_signature) = 0 then
  begin
    AddMessage('    Meta.Signature ' + meta_signature + ' not supported (' + json_data.O['Meta'].S['Name'] + ').');
    Exit;
  end;

  Result := true;
end;

procedure importXYZ(element: IInterface; json_data: TJsonObject);
begin
  SetElementEditValues(element, 'X', json_data.S['X']);
  SetElementEditValues(element, 'Y', json_data.S['Y']);
  SetElementEditValues(element, 'Z', json_data.S['Z']);
end;


procedure ImportCellJson(json_data: TJsonObject);
var
  i: integer;
  cell_items: TJsonArray;
begin
  if not ValidateMetaJSON(json_data, 'CELL') then
    Exit;

  AddMessage('-- import cell json: ' + json_data.O['Meta'].S['Name']);

  if json_data.Contains('Temporary') then
  begin
    cell_items := json_data.A['Temporary'];
    for i := 0 to Pred(cell_items.Count) do begin
      ImportJson(cell_items.O[i]);
    end;
  end;

  if json_data.Contains('Persistent') then
  begin
    cell_items := json_data.A['Persistent'];
    for i := 0 to Pred(cell_items.Count) do begin
      ImportJson(cell_items.O[i]);
    end;
  end;
end;


procedure ImportRefrJson(json_data: TJsonObject);
var
  target_record: IInterface;
begin
  if not ValidateMetaJSON(json_data, 'REFR') then
    Exit;

  target_record := RecordByMeta(json_data);
  if Assigned(target_record) then
  begin
    AddMessage('-- import REFR json: ' + Name(target_record));
    importXYZ(
      ElementByPath(target_record, 'DATA\Rotation'),
      json_data.O['DATA'].O['Rotation']
    );
    importXYZ(
      ElementByPath(target_record, 'DATA\Position'),
      json_data.O['DATA'].O['Offset']
    );
    if json_data.Contains('NAME') then
      ImportJson(json_data.O['NAME']);
  end;
end;


procedure ImportMsttOrStatJson(json_data: TJsonObject);
var
  target_record: IInterface;
begin
  if not ValidateMetaJSON(json_data, 'MSTT,STAT') then
    Exit;

  target_record := RecordByMeta(json_data);
  if Assigned(target_record) then
  begin
    AddMessage('-- import MSTT/STAT json: ' + Name(target_record));
    SetElementEditValues(target_record, 'Model\MODL', json_data.S['MODL']);
    if json_data.Contains('SNTP') then
      ImportJson(json_data.O['SNTP']);
  end;
end;


procedure importStmpEnamNodeJson(enam_element: IInterface; json_data: TJsonObject);
begin
  SetElementEditValues(enam_element, 'Node ID', json_data.S['Node ID']);
  SetElementEditValues(enam_element, 'Node', json_data.S['Node']);
  importXYZ(
    ElementByPath(enam_element, 'Orientation\Rotation'),
    json_data.O['Orientation'].O['Rotation']);
  importXYZ(
    ElementByPath(enam_element, 'Orientation\Offset'),
    json_data.O['Orientation'].O['Offset']);
end;


procedure ImportStmpJson(json_data: TJsonObject);
var
  target_record: IInterface;
  enam_items: TJsonArray;
  enam_item: TJsonObject;
  enam_element: IInterface;
  i: integer;
  max_node_id: integer;
  node_id: string;
begin
  if not ValidateMetaJSON(json_data, 'STMP') then
    Exit;

  target_record := RecordByMeta(json_data);
  if not Assigned(target_record) then
    Exit;

  AddMessage('-- import STMP json: ' + Name(target_record));

  if not json_data.Contains('ENAM') then
  begin
    AddMessage('     missing ENAM');
    Exit;
  end;

  enam_items := json_data.A['ENAM'];
  // cleanup existing enams
  RemoveElement(target_record, 'ENAM');
  enam_element := Add(target_record, 'ENAM', true);
  // adding ENAM also adds one node, remove it.
  RemoveByIndex(enam_element, 0, true);
  max_node_id := 0;
  for i := 0 to Pred(enam_items.Count) do begin
    enam_item := enam_items.O[i];
    node_id := StrToInt(enam_item.S['Node ID']);
    if node_id > max_node_id then
      max_node_id := node_id;
    importStmpEnamNodeJson(Add(enam_element, 'ENAM', true), enam_item);
  end;
  SetElementEditValues(target_record, 'INAM', max_node_id + 1);
end;


function ImportJson(json_data: TJsonObject): integer;
var
  start_signature: string;
begin
  if not ValidateMetaJSON(json_data, IMPORTABLE_SIGNATURES) then
  begin
    Result := 1;
    Exit;
  end;

  start_signature := json_data.O['Meta'].S['Signature'];

  if start_signature = 'CELL' then
    ImportCellJson(json_data)

  else if start_signature = 'REFR' then
    ImportRefrJson(json_data)

  else if start_signature = 'MSTT' then
    ImportMsttOrStatJson(json_data)

  else if start_signature = 'STAT' then
    ImportMsttOrStatJson(json_data)

  else if start_signature = 'STMP' then
    ImportStmpJson(json_data)
  ;
end;


function Initialize: integer;
var
  import_file_path: string;
  json_data: TJsonObject;
  open_file_dialog: TOpenDialog;
begin
  Result := 1;
  try
    open_file_dialog := TOpenDialog.Create(nil);
    if open_file_dialog.Execute then begin
      import_file_path := open_file_dialog.FileName;
      json_data := TJsonObject.Create;
      json_data.LoadFromFile(import_file_path);
      AddMessage('JSON file loaded: ' + import_file_path);
      Result := 0;
    end;
  finally
    open_file_dialog.Free;
  end;

  Result := ImportJson(json_data);

  json_data.Free;
end;

end.
