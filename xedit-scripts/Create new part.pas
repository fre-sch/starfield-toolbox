{
	Create new ship part records by copying existing one.
	Only start at GBFM.
	TODO: find error when starting at COBJ or FLST.
	Those are copied as overrides, and it breaks getting a new FormID when making the CELL override a copy.
  --------------------
	Hotkey: Ctrl+Shift+E
}
unit createnewpart;

Const
  CellPersistentChildren = 8;
  CellTemporaryChildren = 9;
  StartSignatures = 'COBJ,FLST,GBFM,CELL,REFR';

var
  ToFile: IInterface;
  SearchEDID: string;
  ReplaceEDID: string;


procedure CloneRecordElements(old_record, new_record: IInterface);
var
  i: integer;
  element: IInterface;
begin
  for i := 1 to Pred(ElementCount(old_record)) do begin
    element := ElementByIndex(old_record, i);
    wbCopyElementToRecord(element, new_record, False, True);
    AddMessage('i: ' + IntToStr(i) + ', Sig: ' + Signature(element) + ' Elements: ' + IntToStr(ElementCount(element)));
  end;
end;


procedure UpdateEditorID(elem: IInterface);
var
  oldEdid: string;
  newEdid: string;
begin
  oldEdid := EditorID(elem);
  newEdid := StringReplace(
    oldEdid, SearchEDID, ReplaceEDID,
    [rfReplaceAll, rfIgnoreCase]);
  if SameText(newEdid, oldEdid) then
    newEdid := oldEdid + '_COPY';
  SetEditorID(elem, newEdid);
end;


function ProcessMSTT(mstt: IInterface): IInterface;
var
    stmp: IInterface;
    copySTMP: IInterface;
begin
    AddMessage('-- MSTT: ' + Name(mstt));
    Result := wbCopyElementToFile(mstt, ToFile, True, True);
    UpdateEditorID(Result);
    AddMessage('    copy as new: ' + Name(Result));
    stmp := LinksTo(ElementBySignature(mstt, 'SNTP'));
    AddMessage('-- STMP: ' + Name(stmp));
    copySTMP := wbCopyElementToFile(stmp, ToFile, True, True);
    // set it first, so it contains the orientation phrase which is then
    // replaced in UpdateEditorID
    SetEditorID(copySTMP, 'ShipSnap_' + EditorID(mstt));
    UpdateEditorID(copySTMP);
    AddMessage('    copy as new: ' + Name(copySTMP));
    SetEditValue(ElementBySignature(Result, 'SNTP'), Name(copySTMP));
end;


procedure ProcessREFR(refr: IInterface);
var
  refNameElement: IInterface;
  refLinkedElement: IInterface;
  copyMSTT: IInterface;
begin
    refNameElement := ElementBySignature(refr, 'NAME');
    refLinkedElement := LinksTo(refNameElement);
    if Signature(refLinkedElement) = 'MSTT' then begin
      copyMSTT := ProcessMSTT(refLinkedElement);
      SetEditValue(refNameElement, Name(copyMSTT));
    end;
end;


procedure CloneCellGroup(old_cell_group, new_cell: IInterface);
var
  i: integer;
  old_cell_subrecord: IInterface;
  new_cell_subrecord: IInterface;
begin
  AddMessage('-- CLONE GROUP')
  for i := 0 to Pred(ElementCount(old_cell_group)) do begin
    old_cell_subrecord := ElementByIndex(old_cell_group, i);
    AddMessage('    Subrecord: ' + ShortName(old_cell_subrecord) + ' ' + GetElementEditValues(old_cell_subrecord, 'NAME'));
    AddMessage('    FullPath: ' + FullPath(old_cell_subrecord));
    new_cell_subrecord := Add(new_cell, Signature(old_cell_subrecord), True);
    CloneRecordElements(old_cell_subrecord, new_cell_subrecord);
    SetIsPersistent(new_cell_subrecord, GetIsPersistent(old_cell_subrecord));
    if Signature(new_cell_record) = 'REFR' then
      ProcessREFR(new_cell_record);
  end;
end;


procedure CloneCellGroups(old_cell, new_cell: IInterface);
var
  old_cell_group: IInterface;
begin
  old_cell_group := FindChildGroup(ChildGroup(old_cell), CellPersistentChildren, old_cell);
  AddMessage('    persistent children: ' + IntToStr(ElementCount(old_cell_group)));
  CloneCellGroup(old_cell_group, new_cell);

  old_cell_group := FindChildGroup(ChildGroup(old_cell), CellTemporaryChildren, old_cell);
  AddMessage('    temporary children: ' + IntToStr(ElementCount(old_cell_group)));
  CloneCellGroup(old_cell_group, new_cell);
end;


function ProcessCELL(cell: IInterface): IInterface;
var
  i: integer;
  refs: IInterface;
  cellChildGroup: IInterface;
  group_cell, new_cell: IInterface;
begin
  AddMessage('-- CELL: ' + Name(cell));
  if not HasGroup(ToFile, 'CELL') then
    Add(ToFile, 'CELL', True);
  group_cell := GroupBySignature(ToFile, 'CELL');
  new_cell := Add(group_cell, 'CELL', True);
  CloneRecordElements(old_cell, new_cell);
  UpdateEditorID(new_cell);
  AddMessage('    copy as new record: ' + Name(new_cell));
  CloneCellGroups(old_cell, new_cell);
  Result := new_cell;
end;


function ProcessPKIN(pkin: IInterface): IInterface;
var
  cell: IInterface;
  cellNewFormId: cardinal;
  cellOldFormId: cardinal;
begin
  AddMessage('-- PKIN: ' + Name(pkin));
  Result := wbCopyElementToFile(pkin, ToFile, True, True);
  AddMessage('    copy as new record: ' + Name(Result));
  UpdateEditorID(Result);
  cell := LinksTo(ElementByPath(Result, 'CNAM'));
  cell := ProcessCELL(cell, ToFile);
  SetEditValue(ElementByPath(Result, 'CNAM'), Name(cell));
  // CompareExchangeFormID(Result, cellOldFormId, cellNewFormId);
end;


procedure ProcessGBFMComponentLinkedForms(item: IInterface);
var
  formLinks: IInterface;
  formLinkItem: IInterface;
  pkin: IInterface;
  copyPkin: IInterface;
  i: integer;
begin
  if GetEditValue(ElementBySignature(item, 'BFCB')) <> 'BGSFormLinkData_Component' then Exit;
  AddMessage('-- GBFM Linked Forms: ' + Name(item));
  formLinks := ElementByPath(item, 'ITMC\Linked Forms');
  AddMessage('    Form Links Count: ' + IntToStr(ElementCount(formLinks)));
  for i := 0 to Pred(ElementCount(formLinks)) do begin
    formLinkItem := ElementByIndex(formLinks, i);
    pkin := LinksTo(ElementBySignature(formLinkItem, 'FLFM'));
    copyPkin := ProcessPKIN(pkin);
    SetElementEditValues(formLinkItem, 'FLFM', Name(copyPkin));
  end;
end;


function ProcessGBFM(gbfm: IInterface): IInterface;
var
  component: IInterface;
  componentList: IInterface;
  i: integer;
begin
  AddMessage('-- GBFM: ' + Name(gbfm));
  Result := wbCopyElementToFile(gbfm, ToFile, True, True);
  UpdateEditorID(Result);
  AddMessage('    copy as new: ' + Name(Result));
  componentList := ElementByPath(Result, 'Components');
  for i := 0 to Pred(ElementCount(componentList)) do begin
    component := ElementByIndex(componentList, i);
    ProcessGBFMComponentLinkedForms(component);
  end;
end;


// TODO: reenable and use once the FormID conflict is resolved
function ProcessFLST(flst: IInterface): IInterface;
var
  formIdList: IInterface;
  entity: IInterface;
  listElement: IInterface;
  i: integer;
begin
  AddMessage('-- FLST:' + Name(flst));
  AddMessage('    copy as override');
  flst := wbCopyElementToFile(flst, ToFile, False, True);
  formIdList := ElementByPath(flst, 'FormIDs');
  for i := 0 to Pred(ElementCount(formIdList)) do begin
    listElement := ElementByIndex(formIdList, i);
    entity := LinksTo(listElement);
    SetEditValue(listElement, Name(ProcessGBFM(entity)));
  end;
  Result := flst;
end;


// TODO: reenable and use once the FormID conflict is resolved
procedure ProcessCOBJ(cobj: IInterface);
var
  cnam: IInterface;
  cnamCopy: IInterface;
begin
  AddMessage('-- COBJ:' + Name(cobj));
  AddMessage('    copy as override');
  wbCopyElementToFile(cobj, ToFile, False, True);
  cnam := LinksTo(ElementBySignature(cobj, 'CNAM'));
  if Assigned(cnam) then begin
    if Signature(cnam) = 'GBFM' then begin
        cnamCopy := ProcessGBFM(cnam);
        SetElementEditValues(cnamCopy, 'CNAM', Name(cnamCopy));
      end
    else begin
        cnamCopy := ProcessFLST(cnam);
        SetElementEditValues(cnamCopy, 'CNAM', Name(cnamCopy));
    end;
  end;
end;


function FileDialog(e: IInterface): integer;
var
  i: integer;
  frm: TForm;
  clb: TCheckListBox;
begin
  Result := 0;
  if not Assigned(ToFile) then begin
    frm := frmFileSelect;
    try
      frm.Caption := 'Select a plugin';
      clb := TCheckListBox(frm.FindComponent('CheckListBox1'));
      clb.Items.Add('<new file>');
      for i := Pred(FileCount) downto 0 do
        if GetFileName(e) <> GetFileName(FileByIndex(i)) then
          clb.Items.InsertObject(1, GetFileName(FileByIndex(i)), FileByIndex(i))
        else
          Break;
      if frm.ShowModal <> mrOk then begin
        Result := 1;
        Exit;
      end;
      for i := 0 to Pred(clb.Items.Count) do
        if clb.Checked[i] then begin
          if i = 0 then ToFile := AddNewFile else
            ToFile := ObjectToElement(clb.Items.Objects[i]);
          Break;
        end;
    finally
      frm.Free;
    end;
    if not Assigned(ToFile) then begin
      Result := 1;
      Exit;
    end;
  end;
  AddRequiredElementMasters(e, ToFile, False);
end;


function SearchReplaceDialog(strCaption: string; var strSearch, strReplace: string): integer;
var
  frm: TForm;
  inputSearch: TLabeledEdit;
  inputReplace: TLabeledEdit;
  btnOK: TButton;
  btnCancel: TButton;
  pn: TPanel;
begin
  try
    frm := TForm.Create(nil);
    frm.Caption := strCaption;
    frm.AutoSize := true;

    inputSearch := TLabeledEdit.Create(frm);
    inputSearch.Parent := frm;
    inputSearch.EditLabel.Caption := 'Search for';
    inputSearch.LabelPosition := lpLeft;
    inputSearch.Margins.Top := 4;
    inputSearch.Margins.Bottom := 4;
    inputSearch.Margins.Left := 120;
    inputSearch.Margins.Right := 8;
    inputSearch.AlignWithMargins := true;
    inputSearch.Align := alTop;

    inputReplace := TLabeledEdit.Create(frm);
    inputReplace.Parent := frm;
    inputReplace.EditLabel.Caption := 'Replace with';
    inputReplace.LabelPosition := lpLeft;
    inputReplace.Margins.Top := 4;
    inputReplace.Margins.Bottom := 4;
    inputReplace.Margins.Left := 120;
    inputReplace.Margins.Right := 8;
    inputReplace.AlignWithMargins := true;
    inputReplace.Align := alTop;

    pn := TPanel.Create(frm);
    pn.Parent := frm;
    pn.Margins.Top := 4;
    pn.Margins.Bottom := 4;
    pn.Margins.Left := 0;
    pn.Margins.Right := 0;
    pn.AlignWithMargins := true;
    pn.AutoSize := true;
    pn.Align := alTop;
    pn.BevelWidth := 0;

    btnOK := TButton.Create(frm);
    btnOK.Parent := pn;
    btnOK.Caption := 'OK';
    btnOK.Margins.Left := 4;
    btnOK.Margins.Right := 4;
    btnOK.AlignWithMargins := true;
    btnOK.Align := alRight;
    btnOK.ModalResult := mrOk;

    btnCancel := TButton.Create(frm);
    btnCancel.Parent := pn;
    btnCancel.Caption := 'Cancel';
    btnCancel.Margins.Left := 4;
    btnCancel.Margins.Right := 8;
    btnCancel.AlignWithMargins := true;
    btnCancel.Align := alRight;
    btnCancel.ModalResult := mrCancel;

    Result := frm.ShowModal;

    strSearch := inputSearch.Text;
    strReplace := inputReplace.Text;
  finally
    frm.Free;
  end;
end;

// -----------------------------------------------------------------------------

function Initialize: integer;
begin
  Result := 0;
end;


function Process(element: IInterface): integer;
begin
  Result := 0;
  if Pos(Signature(element), StartSignatures) = 0 then begin
    AddMessage('Got ' + Signature(element) + ', only works with: ' + StartSignatures);
    Result := 1;
    Exit;
  end;

  Result := FileDialog(element);
  if Result <> 0 then Exit;

  Result := SearchReplaceDialog('Change EDID', SearchEDID, ReplaceEDID);
  if Result <> mrOk then Exit;

  if Signature(element) = 'COBJ' then
    ProcessCOBJ(element)
  else if Signature(element) = 'GBFM' then
    ProcessGBFM(element)
  else if Signature(element) = 'REFR' then
    ProcessCELL(element)
  else if Signature(element) = 'FLST' then
    ProcessFLST(element)
  ;
  Result := 0;
end;


function Finalize: integer;
begin
  Result := 0;
end;

end.
