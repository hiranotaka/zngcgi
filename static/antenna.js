CheckboxGroupController.prototype.hide = function () {
	this.checkboxGroup.hide();
	this.checkboxes.invoke("disable");
}

CheckboxGroupController.prototype.show = function () {
	this.checkboxes.invoke("enable");
	this.checkboxGroup.show();
}

CheckboxGroupController.prototype.hideRadioPressed = function (event) {
	this.hide();
};

CheckboxGroupController.prototype.showRadioPressed = function (event) {
	this.show();
};

function insertRadio(checkboxGroup, text, checked) {
	var id = checkboxGroup.identify();
	var name = "__edit_checkbox_group_" + id;
	var attributes = {
		type : "radio",
		name : name
	};
	var radio = new Element("input", attributes);

	var label = new Element("label");
	label.insert(radio);
	label.insert(text);
	checkboxGroup.insert({ before : label });

	return radio;
};

function CheckboxGroupController(checkboxGroup) {
	var checkboxes = checkboxGroup.select("input");
	var hideRadio = insertRadio(checkboxGroup, "All");
	var showRadio = insertRadio(checkboxGroup, "Select...");
	showRadio.checked = true;

	this.checkboxGroup = checkboxGroup;
	this.checkboxes = checkboxes;

	hideRadio.observe("click",
			  this.hideRadioPressed.bindAsEventListener(this));
	showRadio.observe("click",
			  this.showRadioPressed.bindAsEventListener(this));

	if (checkboxes.pluck("checked").all()) {
		this.hide();
		hideRadio.checked = true;
	}
}

function initCheckboxGroup(checkboxGroup) {
	new CheckboxGroupController(checkboxGroup);
}

function initCheckboxGroups() {
	var checkboxGroups = $$("span.checkbox_group");
	checkboxGroups.each(initCheckboxGroup);
}

initCheckboxGroups();
