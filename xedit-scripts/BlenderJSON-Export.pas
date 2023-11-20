{

}
unit ExportToBlenderJSON;

Const
  CellPersistentChildren = 8;
  CellTemporaryChildren = 9;
  StartSignatures = 'CELL,REFR,MSTT,STMP';

var
  OutFilePath: string;


procedure ProcessMeta(element: IInterface; jsonObj: TJsonObject);
begin
  jsonObj.O['Meta'].S['FormID'] := IntToHex64(FixedFormID(element), 8);
  jsonObj.O['Meta'].S['Name'] := Name(element);
  jsonObj.O['Meta'].S['EDID'] := EditorID(element);
  jsonObj.O['Meta'].S['Signature'] := Signature(element);
  jsonObj.O['Meta'].S['FileName'] := GetFileName(GetFile(element));
end;


procedure ProcessOrientation(
  offsetElement: IInterface; rotationElement: IInterface;
  jsonObj: TJsonObject);
var
  offsetJson: TJsonObject;
  rotationJson: TJsonObject;

begin
  offsetJson := jsonObj.O['Offset'];
  rotationJson := jsonObj.O['Rotation'];

  offsetJson.S['X'] := GetElementEditValues(offsetElement, 'X');
  offsetJson.S['Y'] := GetElementEditValues(offsetElement, 'Y');
  offsetJson.S['Z'] := GetElementEditValues(offsetElement, 'Z');

  rotationJson.S['X'] := GetElementEditValues(rotationElement, 'X');
  rotationJson.S['Y'] := GetElementEditValues(rotationElement, 'Y');
  rotationJson.S['Z'] := GetElementEditValues(rotationElement, 'Z');
end;


procedure ProcessSTMPNode(nodeElement: IInterface; nodeJson: TJsonObject);
var
  offsetJson: TJsonObject;
  rotationJson: TJsonObject;
begin
  nodeJson.O['Meta'].S['Signature'] := 'STMP.Node';
  nodeJson.S['Node ID'] := GetElementEditValues(nodeElement, 'Node ID');
  nodeJson.S['Name'] := GetElementEditValues(nodeElement, 'Node');
  ProcessOrientation(
    ElementByPath(nodeElement, 'Orientation\Offset'),
    ElementByPath(nodeElement, 'Orientation\Rotation'),
    nodeJson.O['Orientation']);
end;


procedure ProcessSTMP(element: IInterface; jsonObj: TJsonObject);
var
  eNodes: IInterface;
  eNode: IInterface;
  i: Integer;
begin
  ProcessMeta(element, jsonObj);

  eNodes := ElementBySignature(element, 'ENAM');
  for i := 0 to Pred(ElementCount(eNodes)) do begin
    eNode := ElementByIndex(eNodes, i);
    AddMessage('--- node signature: ' + Signature(eNode));
    ProcessSTMPNode(eNode, jsonObj.A['ENAM'].AddObject);
  end;
end;


procedure ProcessMSTTorSTAT(element: IInterface; jsonObj: TJsonObject);
var
  stmp: IInterface;
  modl: IInterface;
begin
  ProcessMeta(element, jsonObj);

  jsonObj.S['MODL'] := GetElementEditValues(element, 'Model\MODL');

  stmp := LinksTo(ElementBySignature(element, 'SNTP'));
  if not Assigned(stmp) then Exit;
  ProcessSTMP(stmp, jsonObj.O['SNTP']);
end;

procedure ProcessRefrData(ref: IInterface; refJsonObj: TJsonObject);
var
  dataElement: IInterface;
begin
  dataElement := ElementBySignature(ref, 'DATA');
  if not Assigned(dataElement) then Exit;
  ProcessOrientation(
    ElementByPath(dataElement, 'Position'),
    ElementByPath(dataElement, 'Rotation'),
    refJsonObj.O['DATA']
  );
end;


procedure ProcessCellRefs(refs: IInterface; parentArray: TJsonArray);
var
  i: integer;
  ref: IInterface;
  refNameElement: IInterface;
  refLinkedElement: IInterface;
  refJsonObj: TJsonObject;
  refLinkedJsonObj: TJsonObject;
begin
  for i := 0 to Pred(ElementCount(refs)) do begin
    ref := ElementByIndex(refs, i);
    refNameElement := ElementBySignature(ref, 'NAME');
    refLinkedElement := LinksTo(refNameElement);
    refJsonObj := parentArray.AddObject;
    ProcessMeta(ref, refJsonObj);
    ProcessRefrData(ref, refJsonObj);
    if Assigned(refLinkedElement) then
    begin
      if Pos(Signature(refLinkedElement), 'MSTT,STAT') > 0 then
        ProcessMSTTorSTAT(refLinkedElement, refJsonObj.O['NAME'])
      else
          ProcessMeta(refLinkedElement, refJsonObj.O['NAME']);
    end;
  end;
end;


procedure ProcessCell(cell: IInterface; jsonObj: TJsonObject);
var
  i: integer;
  refs: IInterface;
  cellChildGroup: IInterface;
begin
  ProcessMeta(cell, jsonObj);

  cellChildGroup := ChildGroup(cell);
  refs := FindChildGroup(cellChildGroup, CellTemporaryChildren, cell);
  ProcessCellRefs(refs, jsonObj.A['Temporary']);

  refs := FindChildGroup(cellChildGroup, CellPersistentChildren, cell);
  ProcessCellRefs(refs, jsonObj.A['Persistent']);
end;


function SaveAs(aFileName: string): string;
var
  dlgSave: TSaveDialog;
begin
  dlgSave := TSaveDialog.Create(nil);
  try
    dlgSave.Options := dlgSave.Options + [ofOverwritePrompt];
    dlgSave.InitialDir := wbDataPath;
    dlgSave.FileName := ExtractFileName(aFileName);
    if dlgSave.Execute then begin
      Result := dlgSave.FileName;
    end;
  finally
    dlgSave.Free;
  end;
end;



function Initialize: integer;
begin
  Result := 0;
  OutFilePath :=  ExtractFilePath(SaveAs('tmp.json'));
end;


function Process(element: IInterface): integer;
var
  jsonObj: TJsonObject;
  childObj: TJsonObject;
  i: integer;
  eNodes: IInterface;
  eNode: IInterface;
begin
  Result := 0;
  if Pos(Signature(element), StartSignatures) = 0 then begin
    AddMessage('Got ' + Signature(element) + ', only works with: ' + StartSignatures);
    Result := 1;
    Exit;
  end;

  jsonObj := TJsonObject.Create;

  if Signature(element) = 'STMP' then
    ProcessSTMP(element, jsonObj)
  else if Signature(element) = 'MSTT' then
    ProcessMSTTorSTAT(element, jsonObj)
  else if Signature(element) = 'STAT' then
    ProcessMSTTorSTAT(element, jsonObj)
  else if Signature(element) = 'CELL' then
    ProcessCell(element, jsonObj)
  else
  begin
    AddMessage('skip: ' + FullPath(element));
    Exit;
  end;

  jsonObj.SaveToFile(
    OutFilePath + '\' + EditorID(element) + '.' + IntToHex64(FixedFormID(element), 8) + '.' + Signature(element) + '.json',
    False, TEncoding.UTF8, True);
  jsonObj.Free;
end;

end.
