{
	Deep copy chain of ship/outpost part records
  --------------------
	Hotkey: Ctrl+Shift+E
}
unit createnewpart;


Const
  CELL_PERSISTENT_CHILDREN = 8;
  CELL_TEMPORARY_CHILDREN = 9;
  START_SIGNATURES = 'COBJ,FLST,GBFM,CELL,REFR';
  MSTT_STAT_COPY_SKIP_EDID = 'PrefabPackinPivotDummy,OutpostGroupPackinDummy';
  EXCLUDE_FILES_MASTERS = 'Starfield.esm,Starfield.exe,BlueprintShips-Starfield.esm,OldMars.esm,Constellation.esm';
  DEFAULT_EDID_SUFFIX = '_COPY';
  DEFAULT_EDID_PREFIX = '';


var
  global_target_file: IInterface;
  global_search_edid: string;
  global_replace_edid: string;
  global_suffix_edid: string;
  global_prefix_edid: string;
  global_cobj_copy: boolean;
  global_flst_copy: boolean;
  global_stat_copy: boolean;
  global_mstt_copy: boolean;
  global_stmp_copy: boolean;


procedure CloneRecordElements(old_record, new_record: IInterface);
var
  i: integer;
  element: IInterface;
begin
  for i := 1 to Pred(ElementCount(old_record)) do begin
    element := ElementByIndex(old_record, i);
    wbCopyElementToRecord(element, new_record, False, True);
    // AddMessage('    i: ' + IntToStr(i) + ', Sig: ' + Signature(element) + ' Elements: ' + IntToStr(ElementCount(element)));
  end;
end;


procedure UpdateEditorID(element: IInterface);
var
  old_value: string;
  new_value: string;
begin
  old_value := EditorID(element);
  new_value := StringReplace(
    old_value, global_search_edid, global_replace_edid,
    [rfReplaceAll]);
  new_value := global_prefix_edid + new_value + global_suffix_edid;
  if not SameText(new_value, old_value) then
    SetEditorID(element, new_value);
end;


function ProcessSTMP(stmp_source: IInterface; mstt_edid: string): IInterface;
var
  stmp_copy: IInterface;
begin
  AddMessage('-- STMP: ' + Name(stmp_source));
  stmp_copy := wbCopyElementToFile(stmp_source, global_target_file, True, True);
  // set it first, so it contains the orientation phrase which is then
  // replaced in UpdateEditorID
  // TODO: this prefix is only useful for ship part data, should be variable
  SetEditorID(stmp_copy, 'ShipSnap_' + mstt_edid);
  UpdateEditorID(stmp_copy);
  AddMessage('    copy as new: ' + Name(stmp_copy));
  Result := stmp_copy;
end;


function ProcessMSTTorSTAT(subrecord_source: IInterface): IInterface;
var
  subrecord_copy: IInterface;
  stmp_source: IInterface;
  stmp_copy: IInterface;
begin
  AddMessage('-- ' + Signature(subrecord_source) + ': ' + Name(subrecord_source));

  if (Signature(subrecord_source) = 'MSTT') and (not global_mstt_copy) then
  begin
    AddMessage('    skipping, global_mstt_copy');
    Exit;
  end;

  if (Signature(subrecord_source) = 'STAT') and (not global_stat_copy) then
  begin
    AddMessage('    skipping, global_stat_copy');
    Exit;
  end;

  if Pos(EditorID(subrecord_source), MSTT_STAT_COPY_SKIP_EDID) > 0 then
  begin
    AddMessage('    skipping, MSTT_STAT_COPY_SKIP_EDID');
    Exit;
  end;

  subrecord_copy := wbCopyElementToFile(subrecord_source, global_target_file, True, True);
  UpdateEditorID(subrecord_copy);
  AddMessage('    copy as new: ' + Name(subrecord_copy));

  stmp_source := LinksTo(ElementBySignature(subrecord_source, 'SNTP'));
  if (Assigned(stmp_source) and global_stmp_copy) then
  begin
    // using the edid of subrecord_source here, otherwise it could turn out as _SUFFIX_SUFFIX
    stmp_copy := ProcessSTMP(stmp_source, EditorID(subrecord_source));
    SetEditValue(ElementBySignature(subrecord_copy, 'SNTP'), Name(stmp_copy));
  end;

  Result := subrecord_copy;
end;


procedure ProcessREFR(refr: IInterface);
var
  ref_name_element: IInterface;
  record_source: IInterface;
  record_copy: IInterface;
begin
    ref_name_element := ElementBySignature(refr, 'NAME');
    record_source := LinksTo(ref_name_element);
    record_copy := ProcessElement(record_source);
    if Assigned(record_copy) then
      SetEditValue(ref_name_element, Name(record_copy));
end;


procedure CloneCellGroup(old_cell_group, new_cell: IInterface);
var
  i: integer;
  old_cell_subrecord: IInterface;
  new_cell_subrecord: IInterface;
begin
  AddMessage('-- Clone Cell Group');
  for i := 0 to Pred(ElementCount(old_cell_group)) do begin
    old_cell_subrecord := ElementByIndex(old_cell_group, i);
    AddMessage('    Subrecord: ' + ShortName(old_cell_subrecord) + ' ' + GetElementEditValues(old_cell_subrecord, 'NAME'));
    AddMessage('    FullPath: ' + FullPath(old_cell_subrecord));
    new_cell_subrecord := Add(new_cell, Signature(old_cell_subrecord), True);
    CloneRecordElements(old_cell_subrecord, new_cell_subrecord);
    SetIsPersistent(new_cell_subrecord, GetIsPersistent(old_cell_subrecord));
    ProcessElement(new_cell_subrecord);
  end;
end;


procedure CloneCellGroups(old_cell, new_cell: IInterface);
var
  old_cell_group: IInterface;
begin
  old_cell_group := FindChildGroup(ChildGroup(old_cell), CELL_PERSISTENT_CHILDREN, old_cell);
  AddMessage('    persistent children: ' + IntToStr(ElementCount(old_cell_group)));
  CloneCellGroup(old_cell_group, new_cell);

  old_cell_group := FindChildGroup(ChildGroup(old_cell), CELL_TEMPORARY_CHILDREN, old_cell);
  AddMessage('    temporary children: ' + IntToStr(ElementCount(old_cell_group)));
  CloneCellGroup(old_cell_group, new_cell);
end;


function ProcessCELL(old_cell: IInterface): IInterface;
var
  group_cell, new_cell: IInterface;
begin
  AddMessage('-- CELL: ' + Name(old_cell));
  if not HasGroup(global_target_file, 'CELL') then
    Add(global_target_file, 'CELL', True);
  group_cell := GroupBySignature(global_target_file, 'CELL');
  new_cell := Add(group_cell, 'CELL', True);
  CloneRecordElements(old_cell, new_cell);
  UpdateEditorID(new_cell);
  AddMessage('    copy as new: ' + Name(new_cell));
  CloneCellGroups(old_cell, new_cell);
  Result := new_cell;
end;


function ProcessPKIN(pkin_source: IInterface): IInterface;
var
  pkin_copy: IInterface;
  subrecord_source: IInterface;
  subrecord_copy: IInterface;
begin
  AddMessage('-- PKIN: ' + Name(pkin_source));
  pkin_copy := wbCopyElementToFile(pkin_source, global_target_file, True, True);
  AddMessage('    copy as new: ' + Name(pkin_copy));
  UpdateEditorID(pkin_copy);
  subrecord_source := LinksTo(ElementByPath(pkin_copy, 'CNAM'));
  subrecord_copy := ProcessElement(subrecord_source);
  if Assigned(subrecord_copy) then
    SetEditValue(ElementByPath(pkin_copy, 'CNAM'), Name(subrecord_copy));
  Result := pkin_copy;
end;


procedure ProcessGBFMComponentLinkedForms(item: IInterface);
var
  form_links: IInterface;
  form_link_item: IInterface;
  subrecord_source: IInterface;
  subrecord_copy: IInterface;
  i: integer;
begin
  if GetEditValue(ElementBySignature(item, 'BFCB')) <> 'BGSFormLinkData_Component' then Exit;
  AddMessage('-- GBFM Linked Forms: ' + Name(item));
  form_links := ElementByPath(item, 'ITMC\Linked Forms');
  AddMessage('    Form Links Count: ' + IntToStr(ElementCount(form_links)));
  for i := 0 to Pred(ElementCount(form_links)) do begin
    form_link_item := ElementByIndex(form_links, i);
    subrecord_source := LinksTo(ElementBySignature(form_link_item, 'FLFM'));
    subrecord_copy := ProcessElement(subrecord_source);
    if Assigned(subrecord_copy) then
      SetElementEditValues(form_link_item, 'FLFM', Name(subrecord_copy));
  end;
end;


function ProcessGBFM(gbfm_source: IInterface): IInterface;
var
  gbfm_copy: IInterface;
  component: IInterface;
  component_list: IInterface;
  i: integer;
begin
  AddMessage('-- GBFM: ' + Name(gbfm_source));
  gbfm_copy := wbCopyElementToFile(gbfm_source, global_target_file, True, True);
  UpdateEditorID(gbfm_copy);
  AddMessage('    copy as new: ' + Name(gbfm_copy));
  component_list := ElementByPath(gbfm_copy, 'Components');
  for i := 0 to Pred(ElementCount(component_list)) do begin
    component := ElementByIndex(component_list, i);
    ProcessGBFMComponentLinkedForms(component);
  end;

  Result := gbfm_copy;
end;


function ProcessWEAP(weap_source: IInterface): IInterface;
var
  weap_copy: IInterface;
begin
  AddMessage('-- WEAP: ' + Name(weap_source));
  weap_copy := wbCopyElementToFile(weap_source, global_target_file, True, True);
  UpdateEditorID(weap_copy);
  AddMessage('    copy as new: ' + Name(weap_copy));
  Result := weap_copy;
end;


function ProcessFLST(flst_source: IInterface): IInterface;
var
  flst_new: IInterface;
  form_id_list: IInterface;
  subrecord_source: IInterface;
  subrecord_copy: IInterface;
  list_element: IInterface;
  i: integer;
begin
  AddMessage('-- FLST:' + Name(flst_source));
  flst_new := wbCopyElementToFile(flst_source, global_target_file, global_flst_copy, True);
  if global_flst_copy then
  begin
    AddMessage('    copy as new: ' + Name(flst_new));
    UpdateEditorID(flst_new);
  end
  else
    AddMessage('    copy as override: ' + Name(flst_new));

  form_id_list := ElementByPath(flst_new, 'FormIDs');
  for i := 0 to Pred(ElementCount(form_id_list)) do begin
    list_element := ElementByIndex(form_id_list, i);
    subrecord_source := LinksTo(list_element);
    subrecord_copy := ProcessElement(subrecord_source);
    if Assigned(subrecord_copy) then
      SetEditValue(list_element, Name(subrecord_copy));
  end;

  Result := flst_new;
end;


function ProcessCOBJ(cobj_source: IInterface): IInterface;
var
  cobj_new: IInterface;
  subrecord_source: IInterface;
  subrecord_copy: IInterface;
begin
  AddMessage('-- COBJ:' + Name(cobj_source));
  cobj_new := wbCopyElementToFile(cobj_source, global_target_file, global_cobj_copy, True);
  if global_cobj_copy then
  begin
    AddMessage('    copy as new: ' + Name(cobj_new));
    UpdateEditorID(cobj_new);
  end
  else
    AddMessage('    copy as override: ' + Name(cobj_new));

  subrecord_source := LinksTo(ElementBySignature(cobj_source, 'CNAM'));
  if Assigned(subrecord_source) then begin
    subrecord_copy := ProcessElement(subrecord_source);
    if Assigned(subrecord_copy) then
      SetElementEditValues(cobj_new, 'CNAM', Name(subrecord_copy));
  end;

  Result := cobj_new;
end;


function ProcessElement(element: IInterface): IInterface;
var
  element_signature: string;
begin
  element_signature := Signature(element);
  Result := nil;

  if element_signature = 'COBJ' then
    Result := ProcessCOBJ(element)

  else if element_signature = 'FLST' then
    Result := ProcessFLST(element)

  else if element_signature = 'GBFM' then
    Result := ProcessGBFM(element)

  else if element_signature = 'REFR' then
    Result := ProcessREFR(element)

  else if element_signature = 'CELL' then
    Result := ProcessCELL(element)

  else if element_signature = 'STAT' then
    Result := ProcessMSTTorSTAT(element)

  else if element_signature = 'MSTT' then
    Result := ProcessMSTTorSTAT(element)

  else if element_signature = 'PKIN' then
    Result := ProcessPKIN(element)

  else if element_signature = 'STMP' then
    Result := ProcessSTMP(element)

  else if element_signature = 'WEAP' then
    Result := ProcessWEAP(element)

  else
    AddMessage('unhandled signature ' + element_signature + ', element ' + Name(element))
  ;
end;


// -----------------------------------------------------------------------------

function FileDialog(element: IInterface; var target_file: IInterface): integer;
var
  i: integer;
  frm: TForm;
  clb: TCheckListBox;
  current_file: IInterface;
  current_file_name: string;
begin
  Result := 0;

  frm := frmFileSelect;
  try
    frm.Caption := 'Select a plugin';
    clb := TCheckListBox(frm.FindComponent('CheckListBox1'));

    for i := Pred(FileCount) downto 0 do
    begin
      current_file := FileByIndex(i);
      current_file_name := GetFileName(current_file);
      if Pos(current_file_name, EXCLUDE_FILES_MASTERS) = 0 then
        clb.Items.InsertObject(0, current_file_name, current_file);
    end;

    if frm.ShowModal <> mrOk then begin
      Result := 1;
      Exit;
    end;

    for i := 0 to Pred(clb.Items.Count) do
      if clb.Checked[i] then begin
        target_file := ObjectToElement(clb.Items.Objects[i]);
        Break;
      end;

  finally
    frm.Free;
  end;

  if not Assigned(target_file) then begin
    Result := 1;
    Exit;
  end;

  if GetFileName(element) = GetFileName(target_file) then
  begin
    global_cobj_copy := true;
    global_flst_copy := true;
  end;

  AddRequiredElementMasters(element, target_file, False);
end;


procedure SetMarginsLayout(
    control: TControl;
    margin_top, margin_bottom, margin_left, margin_right: integer;
    align: integer);
begin
    control.Margins.Top := margin_top;
    control.Margins.Bottom := margin_bottom;
    control.Margins.Left := margin_left;
    control.Margins.Right := margin_right;
    control.AlignWithMargins := true;
    control.Align := align;
end;


procedure DoPanelLayout(panel: TPanel; caption: string);
begin
  if Length(caption) > 0 then
  begin
    panel.Caption := caption;
    panel.ShowCaption := true;
    panel.VerticalAlignment := 0;
    panel.Alignment := 0;
  end;
  panel.BevelOuter := 0;
  panel.AutoSize := true;
  SetMarginsLayout(panel, 4, 8, 8, 8, alTop);
end;


function OptionsDialog(strCaption: string): integer;
var
  frm: TForm;
  options_panel: TPanel;
  update_edit_panel: TPanel;
  input_search: TLabeledEdit;
  input_replace: TLabeledEdit;
  input_suffix: TLabeledEdit;
  input_prefix: TLabeledEdit;
  button_ok: TButton;
  button_cancel: TButton;
  button_panel: TPanel;
  cobj_copy: TCheckBox;
  flst_copy: TCheckBox;
  stat_copy: TCheckBox;
  mstt_copy: TCheckBox;
  stmp_copy: TCheckBox;
begin
  try
    frm := TForm.Create(nil);
    frm.Caption := strCaption;
    frm.AutoSize := true;

    options_panel := TPanel.Create(frm);
    options_panel.Parent := frm;
    DoPanelLayout(options_panel, 'Options');

    cobj_copy := TCheckBox.Create(frm);
    cobj_copy.Parent := options_panel;
    cobj_copy.Caption := 'COBJ as override (unchecked) or as copy (checked)';
    // disable this if the global var has been set to true (via the same file check in FileDialog)
    cobj_copy.Enabled := not global_cobj_copy;
    cobj_copy.Checked := global_cobj_copy;
    SetMarginsLayout(cobj_copy, 20, 0, 16, 0, alTop);

    flst_copy := TCheckBox.Create(frm);
    flst_copy.Parent := options_panel;
    flst_copy.Caption := 'FLST as override (unchecked) or as copy (checked)';
    // disable this if the global var has been set to true (via the same file check in FileDialog)
    flst_copy.Enabled := not global_flst_copy;
    flst_copy.Checked := global_flst_copy;
    SetMarginsLayout(flst_copy, 0, 0, 16, 0, alTop);

    stat_copy := TCheckBox.Create(frm);
    stat_copy.Parent := options_panel;
    stat_copy.Caption := 'Copy STATs linked by REFR';
    stat_copy.Checked := global_stat_copy;
    SetMarginsLayout(stat_copy, 0, 0, 16, 0, alTop);

    mstt_copy := TCheckBox.Create(frm);
    mstt_copy.Parent := options_panel;
    mstt_copy.Caption := 'Copy MSTTs linked by REFR';
    mstt_copy.Checked := global_mstt_copy;
    SetMarginsLayout(mstt_copy, 0, 0, 16, 0, alTop);

    stmp_copy := TCheckBox.Create(frm);
    stmp_copy.Parent := options_panel;
    stmp_copy.Caption := 'Copy STMPs linked by MSTT or STAT';
    stmp_copy.Checked := global_stmp_copy;
    SetMarginsLayout(stmp_copy, 0, 0, 16, 0, alTop);

    update_edit_panel := TPanel.Create(frm);
    update_edit_panel.Parent := frm;
    DoPanelLayout(update_edit_panel, 'Update EDID of copies');

    input_search := TLabeledEdit.Create(frm);
    input_search.Parent := update_edit_panel;
    input_search.EditLabel.Caption := 'Search for';
    input_search.LabelPosition := lpLeft;
    SetMarginsLayout(input_search, 20, 2, 120, 0, alTop);

    input_replace := TLabeledEdit.Create(frm);
    input_replace.Parent := update_edit_panel;
    input_replace.EditLabel.Caption := 'Replace with';
    input_replace.LabelPosition := lpLeft;
    SetMarginsLayout(input_replace, 2, 2, 120, 0, alTop);

    input_prefix := TLabeledEdit.Create(frm);
    input_prefix.Parent := update_edit_panel;
    input_prefix.EditLabel.Caption := 'Add Prefix';
    input_prefix.LabelPosition := lpLeft;
    input_prefix.Text := global_prefix_edid;
    SetMarginsLayout(input_prefix, 2, 2, 120, 0, alTop);

    input_suffix := TLabeledEdit.Create(frm);
    input_suffix.Parent := update_edit_panel;
    input_suffix.EditLabel.Caption := 'Add Suffix';
    input_suffix.LabelPosition := lpLeft;
    input_suffix.Text := global_suffix_edid;
    SetMarginsLayout(input_suffix, 2, 2, 120, 0, alTop);

    button_panel := TPanel.Create(frm);
    button_panel.Parent := frm;
    DoPanelLayout(button_panel, '');

    button_ok := TButton.Create(frm);
    button_ok.Parent := button_panel;
    button_ok.Caption := 'OK';
    button_ok.ModalResult := mrOk;
    SetMarginsLayout(button_ok, 0, 0, 4, 0, alRight);

    button_cancel := TButton.Create(frm);
    button_cancel.Parent := button_panel;
    button_cancel.Caption := 'Cancel';
    button_cancel.ModalResult := mrCancel;
    SetMarginsLayout(button_cancel, 0, 0, 4, 0, alRight);

    Result := frm.ShowModal;

    if Result <> mrOk then
      Exit;

    global_search_edid := input_search.Text;
    global_replace_edid := input_replace.Text;
    global_suffix_edid := input_suffix.Text;
    global_prefix_edid := input_prefix.Text;
    global_cobj_copy := cobj_copy.Checked;
    global_flst_copy := flst_copy.Checked;
    global_stat_copy := stat_copy.Checked;
    global_mstt_copy := mstt_copy.Checked;
    global_stmp_copy := stmp_copy.Checked;
  finally
    frm.Free;
  end;
end;

// -----------------------------------------------------------------------------

function Initialize: integer;
begin
  Result := 0;
  global_cobj_copy := False;
  global_flst_copy := False;
  global_mstt_copy := True;
  global_stat_copy := True;
  global_stmp_copy := True;
  global_prefix_edid := DEFAULT_EDID_PREFIX;
  global_suffix_edid := DEFAULT_EDID_SUFFIX;
end;


function Process(element: IInterface): integer;
begin
  Result := 0;
  if Pos(Signature(element), START_SIGNATURES) = 0 then begin
    AddMessage('Got ' + Signature(element) + ', only works with: ' + START_SIGNATURES);
    Result := 1;
    Exit;
  end;

  Result := FileDialog(element, global_target_file);
  if Result <> 0 then Exit;

  Result := OptionsDialog('Script Options');
  if Result <> mrOk then Exit;

  ProcessElement(element);

  Result := 0;
end;


function Finalize: integer;
begin
  Result := 0;
end;

end.
