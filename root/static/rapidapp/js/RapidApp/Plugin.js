Ext.ns('Ext.ux.RapidApp.Plugin');

/* disabled and replaced by "listener_callbacks"

// Generic plugin that loads a list of event handlers. These 
// should be passed as an array of arrays, where the first
// element of each inner array is the event name, and the rest
// of the items are the handlers (functions) to register

Ext.ux.RapidApp.Plugin.EventHandlers = Ext.extend(Ext.util.Observable,{

	init: function(cmp) {
		if (! Ext.isArray(cmp.event_handlers)) { return true; }
		
		Ext.each(cmp.event_handlers,function(item) {
			if (! Ext.isArray(item)) { throw "invalid element found in event_handlers (should be array of arrays)"; }
			
			var event = item.shift();
			Ext.each(item,function(handler) {
				//Add handler:
				cmp.on(event,handler);
			});
		});
	}
});
Ext.preg('rappeventhandlers',Ext.ux.RapidApp.Plugin.EventHandlers);
*/


/* 2011-03-25 by HV:
 This is my solution to the problem described here:
 http://www.sencha.com/forum/showthread.php?92215-Toolbar-resizing-problem
*/
Ext.ux.RapidApp.Plugin.AutoWidthToolbars = Ext.extend(Ext.util.Observable,{
	init: function(cmp) {
		if(! cmp.getTopToolbar) { return; }
		cmp.on('afterrender',function(c) {
			var tbar = c.getTopToolbar();
			if(tbar) {
				this.setAutoSize(tbar);
			}
			var bbar = c.getBottomToolbar();
			if(bbar) {
				this.setAutoSize(bbar);
			}
		},this);
	},
	setAutoSize: function(toolbar) {
		var El = toolbar.getEl();
		El.setSize('auto');
		El.parent().setSize('auto');
	}
});
Ext.preg('autowidthtoolbars',Ext.ux.RapidApp.Plugin.AutoWidthToolbars);

Ext.ns('Ext.ux.RapidApp.Plugin.HtmlEditor');
Ext.ux.RapidApp.Plugin.HtmlEditor.SimpleCAS_Image = Ext.extend(Ext.ux.form.HtmlEditor.Image,{
	
	constructor: function(cnf) {
		Ext.apply(this,cnf);
	},
	
	maxImageWidth: null,
	
	resizeWarn: false,
	
	onRender: function() {
		var btn = this.cmp.getToolbar().addButton({
				text: 'Insert Image',
				iconCls: 'x-edit-image',
				handler: this.selectImage,
				scope: this,
				tooltip: {
					title: this.langTitle
				},
				overflowText: this.langTitle
		});
	},
	
	selectImage: function() {
		var upload_field = {
			xtype: 'fileuploadfield',
			emptyText: 'Select image',
			fieldLabel:'Select Image',
			name: 'Filedata',
			buttonText: 'Browse',
			width: 300
		};
		
		var fieldset = {
			style: 'border: none',
			hideBorders: true,
			xtype: 'fieldset',
			labelWidth: 70,
			border: false,
			items:[ upload_field ]
		};
		
		var callback = function(form,res) {
			var img = Ext.decode(res.response.responseText);
			
			if(this.resizeWarn && img.resized) {
				Ext.Msg.show({
					title:'Notice: Image Resized',
					msg: 
						'The image has been resized by the server.<br><br>' +
						'Original Size: <b>' + img.orig_width + 'x' + img.orig_height + '</b><br><br>' +
						'New Size: <b>' + img.width + 'x' + img.height + '</b>'
					,
					buttons: Ext.Msg.OK,
					icon: Ext.MessageBox.INFO
				});
			}
			
			img.link_url = '/simplecas/fetch_content/' + img.checksum + '/' + img.filename;
			this.insertImage(img);
		};
		
		var url = '/simplecas/upload_image';
		if(this.maxImageWidth) { url += '/' + this.maxImageWidth; }
		
		Ext.ux.RapidApp.WinFormPost.call(this,{
			title: 'Insert Image',
			width: 430,
			height:140,
			url: url,
			useSubmit: true,
			fileUpload: true,
			fieldset: fieldset,
			success: callback
		});
	},

	insertImage: function(img) {
		if(!this.cmp.activated) {
			this.cmp.onFirstFocus();
		}
		this.cmp.insertAtCursor(
			'<img src="' + img.link_url + '" width=' + img.width + ' height=' + img.height + '>'
		);
	}
});
Ext.preg('htmleditor-casimage',Ext.ux.RapidApp.Plugin.HtmlEditor.SimpleCAS_Image);

Ext.ux.RapidApp.Plugin.HtmlEditor.DVSelect = Ext.extend(Ext.util.Observable, {
	
	// This should be defined in consuming class
	dataview: { xtype: 'panel', 	html: '' },
	
	// This should be defined in consuming class
	getInsertStr: function(Records) {},
	
	title: 'Select Item',
	height: 400,
	width: 500,
	
	constructor: function(cnf) {
		Ext.apply(this,cnf);
	},
	
	init: function(cmp){
		this.cmp = cmp;
		this.cmp.on('render', this.onRender, this);
		
		if(Ext.isIE) {
			// Need to do this in IE because if the user tries to insert an image before the editor
			// is "activated" it will go no place. Unlike FF, in IE the only way to get it activated
			// is to click in it. The editor will automatically enable its toolbar buttons again when
			// its activated.
			this.cmp.on('afterrender',this.disableToolbarInit, this,{delay:1000, single: true});
		}
	},
	
	disableToolbarInit: function() {
		if(!this.cmp.activated) {
			this.cmp.getToolbar().disable();
		}
	},
	
	onRender: function() {
		
		this.btn = this.cmp.getToolbar().addButton({
				iconCls: 'x-edit-image',
				handler: this.loadDVSelect,
				text: this.title,
				scope: this
				//tooltip: {
				//	title: this.langTitle
				//},
				//overflowText: this.langTitle
		});
	},
	
	insertContent: function(str) {
		if(!this.cmp.activated) {
			// This works in FF, but not in IE:
			this.cmp.onFirstFocus();
		}
		this.cmp.insertAtCursor(str);

	},
	
	loadDVSelect: function() {
		
		if (this.dataview_enc) { this.dataview = Ext.decode(this.dataview_enc); }
		
		this.dataview.itemId = 'dv';
		
		this.win = new Ext.Window({
			title: this.title,
			layout: 'fit',
			width: this.width,
			height: this.height,
			closable: true,
			modal: true,
			items: this.dataview,
			buttons: [
				{
					text : 'Select',
					scope: this,
					handler : function() {
						
						var dv = this.win.getComponent('dv');
						
						var recs = dv.getSelectedRecords();
						if (recs.length == 0) { return; }
						
						var str = this.getInsertStr(recs);
						this.win.close();
						return this.insertContent(str);
					}
				},
				{
					text : 'Cancel',
					scope: this,
					handler : function() {
						this.win.close();
					}
				}
			]
		});
		
		this.win.show();
	}
});
Ext.preg('htmleditor-dvselect',Ext.ux.RapidApp.Plugin.HtmlEditor.DVSelect);


Ext.ux.RapidApp.Plugin.HtmlEditor.LoadHtmlFile = Ext.extend(Ext.util.Observable, {
	
	title: 'Load Html',
	height: 400,
	width: 500,
	
	constructor: function(cnf) {
		Ext.apply(this,cnf);
	},
	
	init: function(cmp){
		this.cmp = cmp;
		this.cmp.on('render', this.onRender, this);
	},
	
	onRender: function() {
		
		this.btn = this.cmp.getToolbar().addButton({
				iconCls: 'icon-page-white-world',
				handler: this.selectHtmlFile,
				text: this.title,
				scope: this
				//tooltip: {
				//	title: this.langTitle
				//},
				//overflowText: this.langTitle
		});
	},
	
	replaceContent: function(str) {
		if(!this.cmp.activated) {
			// This works in FF, but not in IE:
			this.cmp.onFirstFocus();
		}
		this.cmp.setValue(str);
	},
	
	selectHtmlFile: function() {
		var upload_field = {
			xtype: 'fileuploadfield',
			emptyText: 'Select html file',
			fieldLabel:'Html File',
			name: 'Filedata',
			buttonText: 'Browse',
			width: 300
		};
		
		var fieldset = {
			style: 'border: none',
			hideBorders: true,
			xtype: 'fieldset',
			labelWidth: 70,
			border: false,
			items:[ upload_field ]
		};
		
		var callback = function(form,res) {
			var packet = Ext.decode(res.response.responseText);
			this.replaceContent(packet.content);
		};
		
		Ext.ux.RapidApp.WinFormPost.call(this,{
			title: 'Load html file',
			width: 430,
			height:140,
			url:'/simplecas/texttranscode/transcode_html',
			useSubmit: true,
			fileUpload: true,
			fieldset: fieldset,
			success: callback
			//failure: callback
		});
	}
});
Ext.preg('htmleditor-loadhtml',Ext.ux.RapidApp.Plugin.HtmlEditor.LoadHtmlFile);


Ext.ux.RapidApp.Plugin.HtmlEditor.InsertFile = Ext.extend(Ext.util.Observable, {
	
	title: 'Insert File',
	height: 400,
	width: 500,
	
	constructor: function(cnf) {
		Ext.apply(this,cnf);
	},
	
	init: function(cmp){
		this.cmp = cmp;
		this.cmp.on('render', this.onRender, this);
		
		var getDocMarkup_orig = this.cmp.getDocMarkup;
		this.cmp.getDocMarkup = function() {
			return '<link rel="stylesheet" type="text/css" href="/static/rapidapp/css/filelink.css" />' +
				getDocMarkup_orig.apply(this,arguments);
		}
	},
	
	onRender: function() {
		this.btn = this.cmp.getToolbar().addButton({
				iconCls: 'icon-page-white-world',
				handler: this.selectFile,
				text: this.title,
				scope: this
				//tooltip: {
				//	title: this.langTitle
				//},
				//overflowText: this.langTitle
		});
	},
	
	insertContent: function(str) {
		if(!this.cmp.activated) {
			// This works in FF, but not in IE:
			this.cmp.onFirstFocus();
		}
		this.cmp.insertAtCursor(str);
	},
	
	selectFile: function() {
		var upload_field = {
			xtype: 'fileuploadfield',
			emptyText: 'Select file',
			fieldLabel:'Select File',
			name: 'Filedata',
			buttonText: 'Browse',
			width: 300
		};
		
		var fieldset = {
			style: 'border: none',
			hideBorders: true,
			xtype: 'fieldset',
			labelWidth: 70,
			border: false,
			items:[ upload_field ]
		};
		
		var callback = function(form,res) {
			var packet = Ext.decode(res.response.responseText);
			var url = '/simplecas/fetch_content/' + packet.checksum + '/' + packet.filename;
			var link = '<a class="' + packet.css_class + '" href="' + url + '">' + packet.filename + '</a>';
			this.insertContent(link);
		};
		
		Ext.ux.RapidApp.WinFormPost.call(this,{
			title: 'Insert file',
			width: 430,
			height:140,
			url:'/simplecas/upload_file',
			useSubmit: true,
			fileUpload: true,
			fieldset: fieldset,
			success: callback
		});
	}
});
Ext.preg('htmleditor-insertfile',Ext.ux.RapidApp.Plugin.HtmlEditor.InsertFile);



Ext.ns('Ext.ux.RapidApp.Plugin');
Ext.ux.RapidApp.Plugin.ClickableLinks = Ext.extend(Ext.util.Observable, {
	
	constructor: function(cnf) {
		Ext.apply(this,cnf);
	},
	
	init: function(cmp){
		this.cmp = cmp;
		
		// if HtmlEditor:
		if(this.cmp.onEditorEvent) {
			var onEditorEvent_orig = this.cmp.onEditorEvent;
			var plugin = this;
			this.cmp.onEditorEvent = function(e) {
				if(e.type == 'click') {  plugin.onClick.apply(this,arguments);  }
				onEditorEvent_orig.apply(this,arguments);
			}
		}
		else {
			this.cmp.on('render', this.onRender, this);
		}
	},
	
	onRender: function() {
		var el = this.cmp.getEl();

		Ext.EventManager.on(el, {
			'click': this.onClick,
			buffer: 100,
			scope: this
		});		
	},
	
	onClick: function(e,el,o) {
		var Element = new Ext.Element(el);
		var href = Element.getAttribute('href');
		if (href && href != '#') {
			document.location.href = href;
		}
	}
});
Ext.preg('clickablelinks',Ext.ux.RapidApp.Plugin.ClickableLinks);


Ext.ns('Ext.ux.RapidApp.Plugin.Combo');
Ext.ux.RapidApp.Plugin.Combo.Addable = Ext.extend(Ext.util.Observable, {
	
	createItemClass: 'appsuperbox-create-item',
	createItemHandler: null,
	
	constructor: function(cnf) { 	
		Ext.apply(this,cnf); 	
	},
	
	init: function(cmp){
		this.cmp = cmp;
		
		Ext.apply(this.cmp,{ classField: 'cls' });
		
		Ext.copyTo(this,this.cmp,[
			'createItemClass',
			'createItemHandler',
			'default_cls'
		]);
		
		Ext.applyIf(this.cmp,{
			tpl: this.getDefaultTpl()
		});
		
		if(Ext.isString(this.cmp.tpl)) {
			var tpl = this.getTplPrepend() + this.cmp.tpl;
			this.cmp.tpl = tpl;
		}
		
		if (this.createItemHandler) {
			this.initCreateItems();
		}
	},
		
	initCreateItems: function() {
		var plugin = this;
		this.cmp.onViewClick = function() {
			var event = arguments[arguments.length - 1]; // <-- last passed argument, the event object;
			if(event) {
				var target = event.getTarget(null,null,true);
				
				// Handle create item instead of normal handler:
				if (target.hasClass(plugin.createItemClass)) {
					this.collapse();
					return plugin.createItemHandler.call(this,plugin.createItemCallback);
				}
			}

			// Original handler:
			this.constructor.prototype.onViewClick.apply(this,arguments);
		};
	},
	
	createItemCallback: function(data) {
		if(! data[this.classField] && this.default_cls) {
			data[this.classField] = this.default_cls;
		}
		var Store = this.getStore();
		var recMaker = Ext.data.Record.create(Store.fields.items);
		var newRec = new recMaker(data);
		Store.insert(0,newRec);
		this.onSelect(newRec,0);
	},
	
	getTplPrepend: function() {
		return '<div style="float:right;"><div class="' + this.createItemClass + '">Create New</div></div>';
	},
	
	getDefaultTpl: function() {
		return 
			'<div class="x-combo-list-item">shit &nbsp;</div>' +
			'<tpl for="."><div class="x-combo-list-item">{' + this.cmp.displayField + '}</div></tpl>';
	}
});
Ext.preg('combo-addable',Ext.ux.RapidApp.Plugin.Combo.Addable);

Ext.ux.RapidApp.Plugin.Combo.AppSuperBox = Ext.extend(Ext.ux.RapidApp.Plugin.Combo.Addable, {
	
	itemLabel: 'items',
	
	init: function(cmp){
		this.cmp = cmp;
		
		if(this.cmp.fieldLabel) { this.itemLabel = this.cmp.fieldLabel; }
		
		Ext.apply(this.cmp,{
			xtype: 'superboxselect', // <-- no effect, the xtype should be set to this in the consuming class
			extraItemCls: 'x-superboxselect-x-flag',
			expandBtnCls: 'icon-roles_expand_sprite',
			listEmptyText: '(no more available ' + this.itemLabel + ')',
			emptyText: '(none)',
			listAlign: 'tr?',
			itemSelector: 'li.x-superboxselect-item',
			stackItems: true
		});
		
		Ext.ux.RapidApp.Plugin.Combo.AppSuperBox.superclass.init.apply(this,arguments);
	},
	
	getDefaultTpl: function() {
		return new Ext.XTemplate(
			'<div class="x-superboxselect x-superboxselect-stacked">',
					'<ul>',
						'<li style="padding-bottom:2px;">',
							'<div style="float:right;"><div class="' + this.createItemClass + '">Create New</div></div>',
							'<div>',
								'Add ' + this.itemLabel + ':',
							'</div>',
						'</li>',
						'<tpl for=".">',
							'<li class="x-superboxselect-item x-superboxselect-x-flag {' + this.cmp.classField + '}">',
								'{' + this.cmp.displayField + '}',
							'</li>',
						'</tpl>',
					'</ul>',
				'</div>'
		);
	}
	
});
Ext.preg('appsuperbox',Ext.ux.RapidApp.Plugin.Combo.AppSuperBox);


Ext.ns('Ext.ux.RapidApp.Plugin');
Ext.ux.RapidApp.Plugin.ReloadServerEvents = Ext.extend(Ext.util.Observable, {
	
	constructor: function(cnf) {
		Ext.apply(this,cnf);
	},
	
	init: function(cmp){
		this.cmp = cmp;
		if(Ext.isArray(this.cmp.reloadEvents)) {
			this.cmp.on('render', this.onRender, this);
		}
	},
	
	onRender: function() {

		var handler = {
			id: this.cmp.id,
			func: function() {
				var store = null;
				if(Ext.isFunction(this.getStore)) { store = this.getStore(); }
				if(! store) { store = this.store; }
				if(store && Ext.isFunction(store.reload)) {
					store.reload();
				}
			}
		};
		
		Ext.each(this.cmp.reloadEvents,function(event) {
			Ext.ux.RapidApp.EventObject.attachServerEvents(handler,event);
		});
	}
	
});
Ext.preg('reload-server-events',Ext.ux.RapidApp.Plugin.ReloadServerEvents);


/*  Modified from Ext.ux.grid.Search for appgrid2 */

// Check RegExp.escape dependency
if('function' !== typeof RegExp.escape) {
	throw('RegExp.escape function is missing. Include Ext.ux.util.js file.');
}

/**
 * Creates new Search plugin
 * @constructor
 * @param {Object} A config object
 */
Ext.ux.RapidApp.Plugin.GridQuickSearch = function(config) {
	Ext.apply(this, config);
	Ext.ux.RapidApp.Plugin.GridQuickSearch.superclass.constructor.call(this);
}; // eo constructor

Ext.extend(Ext.ux.RapidApp.Plugin.GridQuickSearch, Ext.util.Observable, {
	/**
	 * @cfg {Boolean} autoFocus Try to focus the input field on each store load if set to true (defaults to undefined)
	 */

	/**
	 * @cfg {String} searchText Text to display on menu button
	 */
	 searchText:'Quick Search'

	/**
	 * @cfg {String} searchTipText Text to display as input tooltip. Set to '' for no tooltip
	 */ 
	,searchTipText:'Type a text to search and press Enter'

	/**
	 * @cfg {String} selectAllText Text to display on menu item that selects all fields
	 */
	,selectAllText:'Select All'

	/**
	 * @cfg {String} position Where to display the search controls. Valid values are top and bottom
	 * Corresponding toolbar has to exist at least with mimimum configuration tbar:[] for position:top or bbar:[]
	 * for position bottom. Plugin does NOT create any toolbar.(defaults to "bottom")
	 */
	,position:'bottom'

	/**
	 * @cfg {String} iconCls Icon class for menu button (defaults to "icon-magnifier")
	 */
	//,iconCls:'icon-magnifier'
	,iconCls: null

	/**
	 * @cfg {String/Array} checkIndexes Which indexes to check by default. Can be either 'all' for all indexes
	 * or array of dataIndex names, e.g. ['persFirstName', 'persLastName'] (defaults to "all")
	 */
	,checkIndexes:'all'

	/**
	 * @cfg {Array} disableIndexes Array of index names to disable (not show in the menu), e.g. ['persTitle', 'persTitle2']
	 * (defaults to [] - empty array)
	 */
	,disableIndexes:[]

	/**
	 * Field containing search text (read-only)
	 * @property field
	 * @type {Ext.form.TwinTriggerField}
	 */

	/**
	 * @cfg {String} dateFormat How to format date values. If undefined (the default) 
	 * date is formatted as configured in colummn model
	 */

	/**
	 * @cfg {Boolean} showSelectAll Select All item is shown in menu if true (defaults to true)
	 */
	,showSelectAll:true

	/**
	 * Menu containing the column module fields menu with checkboxes (read-only)
	 * @property menu
	 * @type {Ext.menu.Menu}
	 */

	/**
	 * @cfg {String} menuStyle Valid values are 'checkbox' and 'radio'. If menuStyle is radio
	 * then only one field can be searched at a time and selectAll is automatically switched off. 
	 * (defaults to "checkbox")
	 */
	,menuStyle:'checkbox'

	/**
	 * @cfg {Number} minChars Minimum characters to type before the request is made. If undefined (the default)
	 * the trigger field shows magnifier icon and you need to click it or press enter for search to start. If it
	 * is defined and greater than 0 then maginfier is not shown and search starts after minChars are typed.
	 * (defaults to undefined)
	 */

	/**
	 * @cfg {String} minCharsTipText Tooltip to display if minChars is > 1
	 */
	,minCharsTipText:'Type at least {0} characters'

	/**
	 * @cfg {String} mode Use 'remote' for remote stores or 'local' for local stores. If mode is local
	 * no data requests are sent to server the grid's store is filtered instead (defaults to "remote")
	 */
	,mode:'remote'

	/**
	 * @cfg {Array} readonlyIndexes Array of index names to disable (show in menu disabled), e.g. ['persTitle', 'persTitle2']
	 * (defaults to undefined)
	 */

	/**
	 * @cfg {Number} width Width of input field in pixels (defaults to 100)
	 */
	,width:100

	/**
	 * @cfg {String} xtype xtype is usually not used to instantiate this plugin but you have a chance to identify it
	 */
	,xtype:'gridsearch'

	/**
	 * @cfg {Object} paramNames Params name map (defaults to {fields:"fields", query:"query"}
	 */
	,paramNames: {
		 fields:'fields'
		,query:'query'
	}

	/**
	 * @cfg {String} shortcutKey Key to fucus the input field (defaults to r = Sea_r_ch). Empty string disables shortcut
	 */
	,shortcutKey:'r'

	/**
	 * @cfg {String} shortcutModifier Modifier for shortcutKey. Valid values: alt, ctrl, shift (defaults to "alt")
	 */
	,shortcutModifier:'alt'

	/**
	 * @cfg {String} align "left" or "right" (defaults to "left")
	 */

	/**
	 * @cfg {Number} minLength Force user to type this many character before he can make a search 
	 * (defaults to undefined)
	 */

	/**
	 * @cfg {Ext.Panel/String} toolbarContainer Panel (or id of the panel) which contains toolbar we want to render
	 * search controls to (defaults to this.grid, the grid this plugin is plugged-in into)
	 */
	
	// {{{
	/**
	 * @private
	 * @param {Ext.grid.GridPanel/Ext.grid.EditorGrid} grid reference to grid this plugin is used for
	 */
	,init:function(grid) {
		this.grid = grid;

		// setup toolbar container if id was given
		if('string' === typeof this.toolbarContainer) {
			this.toolbarContainer = Ext.getCmp(this.toolbarContainer);
		}

		// do our processing after grid render and reconfigure
		grid.onRender = grid.onRender.createSequence(this.onRender, this);
		grid.reconfigure = grid.reconfigure.createSequence(this.reconfigure, this);
	} // eo function init
	// }}}
	// {{{
	/**
	 * adds plugin controls to <b>existing</b> toolbar and calls reconfigure
	 * @private
	 */
	,onRender:function() {
		var panel = this.toolbarContainer || this.grid;
		var tb = 'bottom' === this.position ? panel.bottomToolbar : panel.topToolbar;
		// add menu
		this.menu = new Ext.menu.Menu();

		// handle position
		if('right' === this.align) {
			tb.addFill();
		}
		else {
			if(0 < tb.items.getCount()) {
				tb.addSeparator();
			}
		}

		// add menu button
		tb.add({
			 text:this.searchText
			,menu:this.menu
			,iconCls:this.iconCls
		});

		// add input field (TwinTriggerField in fact)
		this.field = new Ext.form.TwinTriggerField({
			 width:this.width
			,selectOnFocus:undefined === this.selectOnFocus ? true : this.selectOnFocus
			,trigger1Class:'x-form-clear-trigger'
			,trigger2Class:this.minChars ? 'x-hide-display' : 'x-form-search-trigger'
			,onTrigger1Click:this.onTriggerClear.createDelegate(this)
			,onTrigger2Click:this.minChars ? Ext.emptyFn : this.onTriggerSearch.createDelegate(this)
			,minLength:this.minLength
		});

		// install event handlers on input field
		this.field.on('render', function() {
			// register quick tip on the way to search
			
			/*
			if((undefined === this.minChars || 1 < this.minChars) && this.minCharsTipText) {
				Ext.QuickTips.register({
					 target:this.field.el
					,text:this.minChars ? String.format(this.minCharsTipText, this.minChars) : this.searchTipText
				});
			}
			*/
			
			

			if(this.minChars) {
				this.field.el.on({scope:this, buffer:300, keyup:this.onKeyUp});
			}

			// install key map
			var map = new Ext.KeyMap(this.field.el, [{
				 key:Ext.EventObject.ENTER
				,scope:this
				,fn:this.onTriggerSearch
			},{
				 key:Ext.EventObject.ESC
				,scope:this
				,fn:this.onTriggerClear
			}]);
			map.stopEvent = true;
		}, this, {single:true});

		tb.add(this.field);

		// re-layout the panel if the toolbar is outside
		if(panel !== this.grid) {
			this.toolbarContainer.doLayout();
		}

		// reconfigure
		this.reconfigure();

		// keyMap
		if(this.shortcutKey && this.shortcutModifier) {
			var shortcutEl = this.grid.getEl();
			var shortcutCfg = [{
				 key:this.shortcutKey
				,scope:this
				,stopEvent:true
				,fn:function() {
					this.field.focus();
				}
			}];
			shortcutCfg[0][this.shortcutModifier] = true;
			this.keymap = new Ext.KeyMap(shortcutEl, shortcutCfg);
		}

		if(true === this.autoFocus) {
			this.grid.store.on({scope:this, load:function(){this.field.focus();}});
		}

	} // eo function onRender
	// }}}
	// {{{
	/**
	 * field el keypup event handler. Triggers the search
	 * @private
	 */
	,onKeyUp:function(e, t, o) {

		// ignore special keys 
		if(e.isNavKeyPress()) {
			return;
		}

		var length = this.field.getValue().toString().length;
		if(0 === length || this.minChars <= length) {
			this.onTriggerSearch();
		}
	} // eo function onKeyUp
	// }}}
	// {{{
	/**
	 * Clear Trigger click handler
	 * @private 
	 */
	,onTriggerClear:function() {
		if(this.field.getValue()) {
			this.field.setValue('');
			this.field.focus();
			this.onTriggerSearch();
		}
	} // eo function onTriggerClear
	// }}}
	// {{{
	/**
	 * Search Trigger click handler (executes the search, local or remote)
	 * @private 
	 */
	,onTriggerSearch:function() {
		if(!this.field.isValid()) {
			return;
		}
		var val = this.field.getValue();
		var store = this.grid.store;

		// grid's store filter
		if('local' === this.mode) {
			store.clearFilter();
			if(val) {
				store.filterBy(function(r) {
					var retval = false;
					this.menu.items.each(function(item) {
						if(!item.checked || retval) {
							return;
						}
						var rv = r.get(item.dataIndex);
						rv = rv instanceof Date ? rv.format(this.dateFormat || r.fields.get(item.dataIndex).dateFormat) : rv;
						var re = new RegExp(RegExp.escape(val), 'gi');
						retval = re.test(rv);
					}, this);
					if(retval) {
						return true;
					}
					return retval;
				}, this);
			}
			else {
			}
		}
		// ask server to filter records
		else {
			// clear start (necessary if we have paging)
			if(store.lastOptions && store.lastOptions.params) {
				store.lastOptions.params[store.paramNames.start] = 0;
			}

			// get fields to search array
			var fields = [];
			this.menu.items.each(function(item) {
				if(item.checked) {
					fields.push(item.dataIndex);
				}
			});

			// add fields and query to baseParams of store
			delete(store.baseParams[this.paramNames.fields]);
			delete(store.baseParams[this.paramNames.query]);
			if (store.lastOptions && store.lastOptions.params) {
				delete(store.lastOptions.params[this.paramNames.fields]);
				delete(store.lastOptions.params[this.paramNames.query]);
			}
			if(fields.length) {
				store.baseParams[this.paramNames.fields] = Ext.encode(fields);
				store.baseParams[this.paramNames.query] = val;
			}

			// reload store
			store.reload();
		}

	} // eo function onTriggerSearch
	// }}}
	// {{{
	/**
	 * @param {Boolean} true to disable search (TwinTriggerField), false to enable
	 */
	,setDisabled:function() {
		this.field.setDisabled.apply(this.field, arguments);
	} // eo function setDisabled
	// }}}
	// {{{
	/**
	 * Enable search (TwinTriggerField)
	 */
	,enable:function() {
		this.setDisabled(false);
	} // eo function enable
	// }}}
	// {{{
	/**
	 * Disable search (TwinTriggerField)
	 */
	,disable:function() {
		this.setDisabled(true);
	} // eo function disable
	// }}}
	// {{{
	/**
	 * (re)configures the plugin, creates menu items from column model
	 * @private 
	 */
	,reconfigure:function() {

		// {{{
		// remove old items
		var menu = this.menu;
		menu.removeAll();
		
		

		// add Select All item plus separator
		if(this.showSelectAll && 'radio' !== this.menuStyle) {
			menu.add(new Ext.menu.CheckItem({
				 text:this.selectAllText
				,checked:!(this.checkIndexes instanceof Array)
				,hideOnClick:false
				,handler:function(item) {
					var checked = ! item.checked;
					item.parentMenu.items.each(function(i) {
						if(item !== i && i.setChecked && !i.disabled) {
							i.setChecked(checked);
						}
					});
				}
			}),'-');
		}

		// }}}
		// {{{
		// add new items
		//var cm = this.grid.colModel;
		var columns = this.grid.initialConfig.columns;
		
		var group = undefined;
		if('radio' === this.menuStyle) {
			group = 'g' + (new Date).getTime();	
		}
		//Ext.each(cm.config, function(config) {
		Ext.each(columns, function(config) {
			var disable = false;
			if(config.header && config.dataIndex && !config.no_quick_search) {
				Ext.each(this.disableIndexes, function(item) {
					disable = disable ? disable : item === config.dataIndex;
				});
				if(!disable) {
					menu.add(new Ext.menu.CheckItem({
						 text:config.header
						,hideOnClick:false
						,group:group
						,checked:'all' === this.checkIndexes
						,dataIndex:config.dataIndex
					}));
				}
			}
		}, this);
		// }}}
		// {{{
		// check items
		if(this.checkIndexes instanceof Array) {
			Ext.each(this.checkIndexes, function(di) {
				var item = menu.items.find(function(itm) {
					return itm.dataIndex === di;
				});
				if(item) {
					item.setChecked(true, true);
				}
			}, this);
		}
		// }}}
		// {{{
		// disable items
		if(this.readonlyIndexes instanceof Array) {
			Ext.each(this.readonlyIndexes, function(di) {
				var item = menu.items.find(function(itm) {
					return itm.dataIndex === di;
				});
				if(item) {
					item.disable();
				}
			}, this);
		}
		// }}}

	} // eo function reconfigure
	// }}}

}); 



/*
 Ext.ux.RapidApp.Plugin.GridHmenuColumnsToggle
 2011-06-08 by HV

 Plugin for Ext.grid.GridPanel that converts the 'Columns' hmenu submenu item
 into a Ext.ux.RapidApp.menu.ToggleSubmenuItem (instead of Ext.menu.Item)

 See the Ext.ux.RapidApp.menu.ToggleSubmenuItem class for more details.
*/
Ext.ux.RapidApp.Plugin.GridHmenuColumnsToggle = Ext.extend(Ext.util.Observable,{
	init: function(cmp) {
		this.cmp = cmp;
		cmp.on('afterrender',this.onAfterrender,this);
	},
	
	onAfterrender: function() {
		
		var hmenu = this.cmp.view.hmenu;
		var colsItem = hmenu.getComponent('columns');
		if (!colsItem) { return; }
		colsItem.hide();
		
		hmenu.add(Ext.apply(Ext.apply({},colsItem.initialConfig),{
			xtype: 'menutoggleitem',
			itemId:'columns-new'
		}));
	}
});
Ext.preg('grid-hmenu-columns-toggle',Ext.ux.RapidApp.Plugin.GridHmenuColumnsToggle);


// For use with Fields, returns empty strings as null
Ext.ux.RapidApp.Plugin.EmptyToNull = Ext.extend(Ext.util.Observable,{
	init: function(cmp) {
		var nativeGetValue = cmp.getValue;
		cmp.getValue = function() {
			var value = nativeGetValue.call(cmp);
			if (value == '') { return null; }
			return value;
		}
	}
});
Ext.preg('emptytonull',Ext.ux.RapidApp.Plugin.EmptyToNull);

// For use with Fields, returns nulls as empty string
Ext.ux.RapidApp.Plugin.NullToEmpty = Ext.extend(Ext.util.Observable,{
	init: function(cmp) {
		var nativeGetValue = cmp.getValue;
		cmp.getValue = function() {
			var value = nativeGetValue.call(cmp);
			if (value == null) { return ''; }
			return value;
		}
	}
});
Ext.preg('nulltoempty',Ext.ux.RapidApp.Plugin.NullToEmpty);

// For use with Fields, returns false/true as 0/1
Ext.ux.RapidApp.Plugin.BoolToInt = Ext.extend(Ext.util.Observable,{
	init: function(cmp) {
		var nativeGetValue = cmp.getValue;
		cmp.getValue = function() {
			var value = nativeGetValue.call(cmp);
			if (value == false) { return 0; }
			if (value == true) { return 1; }
			return value;
		}
	}
});
Ext.preg('booltoint',Ext.ux.RapidApp.Plugin.BoolToInt);


// Plugin adds '[+]' to panel title when collapsed if titleCollapse is on
Ext.ux.RapidApp.Plugin.TitleCollapsePlus = Ext.extend(Ext.util.Observable,{
	
	addedString: '',
	
	init: function(cmp) {
		this.cmp = cmp;
		
		if (this.cmp.titleCollapse && this.cmp.title) {
			this.cmp.on('beforecollapse',function(){
				this.updateCollapseTitle.call(this,'collapse');
			},this);
			this.cmp.on('beforeexpand',function(){
				this.updateCollapseTitle.call(this,'expand');
			},this);
			this.cmp.on('afterrender',this.updateCollapseTitle,this);
		}
	},
	
	updateCollapseTitle: function(opt) {
		if (!this.cmp.titleCollapse || !this.cmp.title) { return; }
		
		if(opt == 'collapse') { return this.setTitlePlus(true); }
		if(opt == 'expand') { return this.setTitlePlus(false); }
		
		if(this.cmp.collapsed) {
			this.setTitlePlus(true);
		}
		else {
			this.setTitlePlus(false);
		}
	},
	
	getTitle: function() {
		return this.cmp.title.replace(this.addedString,'');
	},
	
	setTitlePlus: function(bool) {
		var title = this.getTitle();
		if(bool) {
			this.addedString = 
				'&nbsp;<span style="font-weight:lighter;font-family:monospace;color:gray;">' + 
					'&#91;&#43;&#93;' +
				'</span>';
			return this.cmp.setTitle(title + this.addedString);
		}
		this.addedString = '';
		return this.cmp.setTitle(title);
	}
});
Ext.preg('titlecollapseplus',Ext.ux.RapidApp.Plugin.TitleCollapsePlus);

/*
 Ext.ux.RapidApp.Plugin.CmpDataStorePlus
 2011-11-02 by HV

 Plugin for components with stores (such as AppGrid2, AppDV).
 This plugin contains generalized extra functionality applicable
 to any components with stores (note that Ext.data.Store itself
 cannot use plugins because its not a component)
*/
Ext.ux.RapidApp.Plugin.CmpDataStorePlus = Ext.extend(Ext.util.Observable,{
	init: function(cmp) {
		this.cmp = cmp;
		var plugin = this;
		
		var store = this.cmp.store;
		store.undoChanges = function() {
			store.each(function(Record){
					if(Record.phantom) { store.remove(Record); } 
				});
			store.rejectChanges();
			store.fireEvent('update',store);
		};
		store.on('beforeload',store.undoChanges,store);
		
		this.cmp.loadedStoreButtons = {};
		
		this.cmp.getStoreButton = function() {
			return plugin.getStoreButton.apply(plugin,arguments);
		};
		
	},
	
	getStoreButton: function(name) {
		
		if(!this.cmp.loadedStoreButtons[name]) {
			var constructor = this.storeButtonConstructors[name];
			if(! constructor) { return; }
			var btn = constructor({},this.cmp);
			if(!btn) { return; }
			
			this.cmp.loadedStoreButtons[name] = btn;
		}

		return this.cmp.loadedStoreButtons[name];
	},
	
	storeButtonConstructors: {
		
		add: function(cnf,cmp) {
			
			if(!cmp.store.api.create) { return false; }
			
			return new Ext.Button(Ext.apply({
				tooltip: 'Add',
				iconCls: 'icon-add',
				handler: function(btn) {
					var store = cmp.store;
					if(store.proxy.getConnection().isLoading()) { return; }
					var newRec = new store.recordType();
					store.add(newRec);
					if(cmp.persist_immediately) { store.save(); }
				}
			},cnf || {}));
		},
		
		delete: function(cnf,cmp) {
			
			if(!cmp.store.api.destroy) { return false; }
			
			var btn = new Ext.Button(Ext.apply({
				tooltip: 'Delete',
				iconCls: 'icon-delete',
				disabled: true,
				handler: function(btn) {
					var store = cmp.store;
					if(store.proxy.getConnection().isLoading()) { return; }
					store.remove(cmp.getSelectionModel().getSelections());
					if(cmp.persist_immediately) { store.save(); }
				}
			},cnf || {}));
			
			cmp.on('afterrender',function() {
			
				var toggleBtn = function(sm) {
					if (sm.getSelections().length > 0) {
						btn.setDisabled(false);
					}
					else {
						btn.setDisabled(true);
					}
				};
				
				var sm = this.getSelectionModel();
				sm.on('selectionchange',toggleBtn,sm);
			},cmp);
				
			return btn;
		},
		
		reload: function(cnf,cmp) {
			
			return new Ext.Button(Ext.apply({
				tooltip: 'Reload',
				iconCls: 'x-tbar-loading',
				handler: function(btn) {
					var store = cmp.store;
					store.reload();
				}
			},cnf || {}));
		},
		
		save: function(cnf,cmp) {
			
			var api = cmp.store.api;
			if(!api.create && !api.update && !api.destroy) { return false; }
			if(cmp.persist_immediately) { return false; }
			
			var btn = new Ext.Button(Ext.apply({
				tooltip: 'Save',
				iconCls: 'icon-save',
				disabled: true,
				handler: function(btn) {
					var store = cmp.store;
					store.save();
				}
			},cnf || {}));
				
			var toggleBtn = function(store) {
				var modifiedRecords = store.getModifiedRecords();
				if (store.getModifiedRecords().length > 0 || store.removed.length > 0) {
					btn.setDisabled(false);
				}
				else {
					btn.setDisabled(true);
				}
			};
			
			cmp.store.on('load',toggleBtn,cmp.store);
			cmp.store.on('read',toggleBtn,cmp.store);
			cmp.store.on('write',toggleBtn,cmp.store);
			cmp.store.on('datachanged',toggleBtn,cmp.store);
			cmp.store.on('clear',toggleBtn,cmp.store);
			cmp.store.on('update',toggleBtn,cmp.store);
			cmp.store.on('remove',toggleBtn,cmp.store);
			cmp.store.on('add',toggleBtn,cmp.store);
				
			return btn;
		},
		
		undo: function(cnf,cmp) {
			
			var api = cmp.store.api;
			if(!api.create && !api.update && !api.destroy) { return false; }
			if(cmp.persist_immediately) { return false; }
			
			var btn =  new Ext.Button(Ext.apply({
				tooltip: 'Undo',
				iconCls: 'icon-arrow-undo',
				disabled: true,
				handler: function(btn) {
					var store = cmp.store;
					// custom function, see AppGrid2 below
					store.undoChanges.call(store);
				}
			},cnf || {}));
				
			var toggleBtn = function(store) {
				var modifiedRecords = store.getModifiedRecords();
				if (store.getModifiedRecords().length > 0 || store.removed.length > 0) {
					btn.setDisabled(false);
				}
				else {
					btn.setDisabled(true);
				}
			};
			
			cmp.store.on('load',toggleBtn,cmp.store);
			cmp.store.on('read',toggleBtn,cmp.store);
			cmp.store.on('write',toggleBtn,cmp.store);
			cmp.store.on('datachanged',toggleBtn,cmp.store);
			cmp.store.on('clear',toggleBtn,cmp.store);
			cmp.store.on('update',toggleBtn,cmp.store);
			cmp.store.on('remove',toggleBtn,cmp.store);
			cmp.store.on('add',toggleBtn,cmp.store);
				
			return btn;
		}
		
	}

});
Ext.preg('datastore-plus',Ext.ux.RapidApp.Plugin.CmpDataStorePlus);

