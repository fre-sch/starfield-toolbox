{
}
unit ImportBlenderJSON;

const
  CellPersistentChildren = 8;
  CellTemporaryChildren = 9;
  StartSignatures = 'CELL,REFR,MSTT,STMP';


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

function ValidateJSONMeta(jsonObj: TJsonObject): bool;
var
  metaSignature: string;
begin
  Result := false;

  if not jsonObj.Contains('Meta') then
  begin
    AddMessage('"Meta" object missing');
    Exit;
  end;

  if not jsonObj.O['Meta'].Contains('FormID') then
  begin
    AddMessage('"FormID" in meta object missing');
    Exit;
  end;

  if not jsonObj.O['Meta'].Contains('EDID') then
  begin
    AddMessage('"EDID" in meta object missing');
    Exit;
  end;

  if not jsonObj.O['Meta'].Contains('Signature') then
  begin
    AddMessage('"Signature" in meta object missing');
    Exit;
  end;

  metaSignature := jsonObj.O['Meta'].S['Signature'];
  if Pos(metaSignature, StartSignatures) = 0 then
  begin
    AddMessage('Signature ' + metaSignature + ' in meta not supported');
    Exit;
  end;

  Result := true;
end;


function RecordByMeta(jsonObj: TJsonObject): IInterface;
var
  recordFile: IwbFile;
begin
  recordFile := FileByName(jsonObj.O['Meta'].S['FileName']);
  if not Assigned(recordFile) then
  begin
    Result := nil;
    AddMessage('file '+ jsonObj.O['Meta'].S['FileName'] + ' not found for: ' + jsonObj.O['Meta'].S['FormID']);
    Exit;
  end;

  Result := RecordByFormID(
    recordFile,
    StrToInt('$' + jsonObj.O['Meta'].S['FormID']),
    true
  );
  if not Assigned(Result) then
    AddMessage('-- record not found: ' + jsonObj.O['Meta'].S['FormID'])
  else
    AddMessage('-- record found: ' + FullPath(Result));
end;


procedure importCellJson(jsonObj: TJsonObject);
var
  i: integer;
  jsonArr: TJsonArray;
  refrChild: TJsonObject;
begin
  if not ValidateJSONMeta(jsonObj) then
    Exit;

  AddMessage('import cell json: ' + jsonObj.O['Meta'].S['FormID']);
  if jsonObj.Contains('Temporary') then
  begin
    jsonArr := jsonObj.A['Temporary'];
    for i := 0 to Pred(jsonArr.Count) do begin
      importRefrJson(jsonArr.O[i]);
    end;
  end;

  if jsonObj.Contains('Persistent') then
  begin
    jsonArr := jsonObj.A['Persistent'];
    for i := 0 to Pred(jsonArr.Count) do begin
      importRefrJson(jsonArr.O[i]);
    end;
  end;
end;


procedure importRefrJson(jsonObj: TJsonObject);
var
  targetRecord: IInterface;
  recordFile: IwbFile;
begin
  if not ValidateJSONMeta(jsonObj) then
    Exit;
  AddMessage('import REFR json: ' + jsonObj.O['Meta'].S['FormID']);
  targetRecord := RecordByMeta(jsonObj);
end;


procedure importMttStatJson(jsonObj: TJsonObject);
begin
  AddMessage('import mstt/stat json');
end;


procedure importRotation(element: IInterface; jsonObj: TJsonObject);
begin
  SetElementEditValues(element, 'X', jsonObj.S['X']);
  SetElementEditValues(element, 'Y', jsonObj.S['Y']);
  SetElementEditValues(element, 'Z', jsonObj.S['Z']);
end;


procedure importOffset(element: IInterface; jsonObj: TJsonObject);
begin
  SetElementEditValues(element, 'X', jsonObj.S['X']);
  SetElementEditValues(element, 'Y', jsonObj.S['Y']);
  SetElementEditValues(element, 'Z', jsonObj.S['Z']);
end;


procedure importStmpEnamNodeJson(enamNode: IInterface; jsonObj: TJsonObject);
var
  i: integer;
  orientElement: IInterface;
begin
  SetElementEditValues(enamNode, 'Node ID', jsonObj.S['Node ID']);
  SetElementEditValues(enamNode, 'Node', jsonObj.S['Node']);
  importRotation(
    ElementByPath(enamNode, 'Orientation\Rotation'),
    jsonObj.O['Orientation'].O['Rotation']);
  importOffset(
    ElementByPath(enamNode, 'Orientation\Offset'),
    jsonObj.O['Orientation'].O['Offset']);
end;


procedure importSTMPJson(jsonObj: TJsonObject);
var
  targetRecord: IInterface;
  enamJson: TJsonArray;
  enamItemJson: TJsonObject;
  enamElement: IInterface;
  i: integer;
  maxNodeId: integer;
  nodeId: string;
begin
  if not ValidateJSONMeta(jsonObj) then
    Exit;
  AddMessage('import STMP json: ' + jsonObj.O['Meta'].S['FormID']);
  targetRecord := RecordByMeta(jsonObj);
  if not jsonObj.Contains('ENAM') then
  begin
    AddMessage('missing ENAM');
    Exit;
  end;

  enamJson := jsonObj.A['ENAM'];
  // cleanup existing enams
  RemoveElement(targetRecord, 'ENAM');
  enamElement := Add(targetRecord, 'ENAM', true);
  // adding ENAM also adds one node, remove it.
  RemoveByIndex(enamElement, 0, true);
  maxNodeId := 0;
  for i := 0 to Pred(enamJson.Count) do begin
    enamItemJson := enamJson.O[i];
    nodeId := StrToInt(enamItemJson.S['Node ID']);
    if nodeId > maxNodeId then
      maxNodeId := nodeId;
    importStmpEnamNodeJson(Add(enamElement, 'ENAM', true), enamItemJson);
  end;
  SetElementEditValues(targetRecord, 'INAM', maxNodeId + 1);
end;


function Initialize: integer;
var
  importFilePath: string;
  importJsonObj: TJsonObject;
  dlgOpenFile: TOpenDialog;
  metaJson: TJsonObject;
  startSignature: string;
begin
  Result := 1;
  try
    dlgOpenFile := TOpenDialog.Create(nil);
    if dlgOpenFile.Execute then begin
      importFilePath := dlgOpenFile.FileName;
      importJsonObj := TJsonObject.Create;
      importJsonObj.LoadFromFile(importFilePath);
      AddMessage('JSON file loaded: ' + importFilePath);
      Result := 0;
    end;
  finally
    dlgOpenFile.Free;
  end;

  if not ValidateJSONMeta(importJsonObj) then
  begin
    Result := 1;
    Exit;
  end;

  startSignature := importJsonObj.O['Meta'].S['Signature'];

  if startSignature = 'CELL' then
    importCellJson(importJsonObj)
  else if startSignature = 'REFR' then
    importRefrJson(importJsonObj)
  else if startSignature = 'MSTT' then
    importMttStatJson(importJsonObj)
  else if startSignature = 'STAT' then
    importMttStatJson(importJsonObj)
  else if startSignature = 'STMP' then
    importSTMPJson(importJsonObj)
  ;

  importJsonObj.Free;
end;

end.
