___INFO___

{
  "type": "TAG",
  "id": "cvt_temp_public_id",
  "version": 1,
  "securityGroups": [],
  "displayName": "Hubspot Form Submission Listener",
  "brand": {
    "id": "brand_dummy",
    "displayName": ""
  },
  "description": "Template permettant d\u0027écouter les événements de soumission de formulaire Hubspot peu importe sa version (v3 ou v4)",
  "containerContexts": [
    "WEB"
  ]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "SELECT",
    "name": "formType",
    "displayName": "Version du formulaire HubSpot",
    "macrosInSelect": false,
    "selectItems": [
      {
        "value": "form_v3",
        "displayValue": "Formulaires v3"
      },
      {
        "value": "form_v4",
        "displayValue": "Formulaires v4"
      },
      {
        "value": "form_both",
        "displayValue": "Formulaires v3 et v4"
      }
    ],
    "simpleValueType": true
  },
  {
    "type": "TEXT",
    "name": "eventName",
    "displayName": "Nom de l\u0027événement dataLayer",
    "simpleValueType": true,
    "defaultValue": "hubspot-form-success",
    "help": "Nom de l\u0027événement qui sera envoyé au dataLayer lors d\u0027une soumission de formulaire réussie."
  },
  {
    "type": "CHECKBOX",
    "name": "includeFormData",
    "checkboxText": "Inclure les données du formulaire",
    "simpleValueType": true,
    "defaultValue": true,
    "help": "Si activé, les données du formulaire seront incluses dans le dataLayer push (email, nom, etc.)."
  }
]


___SANDBOXED_JS_FOR_WEB_TEMPLATE___

// Importation des API nécessaires
var createQueue = require('createQueue');
var createArgumentsQueue = require('createArgumentsQueue');
var injectScript = require('injectScript');
var callInWindow = require('callInWindow');
var copyFromWindow = require('copyFromWindow');
var setInWindow = require('setInWindow');
var logToConsole = require('logToConsole');
var makeTableMap = require('makeTableMap');
var makeNumber = require('makeNumber');
var makeString = require('makeString');
var getTimestamp = require('getTimestamp');
var encodeUriComponent = require('encodeUriComponent');

// Récupération des paramètres du template
var formType = data.formType;
var eventName = data.eventName || 'hubspot-form-success';
var includeFormData = data.includeFormData !== false;

// Création de la file d'attente dataLayer si elle n'existe pas
var dataLayerPush = createQueue('dataLayer');

// Fonction de succès et d'échec
var onSuccess = function() {
  data.gtmOnSuccess();
};

var onFailure = function() {
  data.gtmOnFailure();
};

// Fonction pour nettoyer les noms de champs (sans utiliser d'expression régulière littérale)
var cleanFieldName = function(name) {
  var result = '';
  for (var i = 0; i < name.length; i++) {
    var char = name.charAt(i);
    // Vérifier si le caractère est une lettre, un chiffre ou un underscore
    if ((char >= 'a' && char <= 'z') || 
        (char >= 'A' && char <= 'Z') || 
        (char >= '0' && char <= '9') || 
        char === '_') {
      result += char;
    } else {
      result += '_';
    }
  }
  return result;
};

// --- Script pour les formulaires V4 ---
var setupV4Listener = function() {
  // Vérifier si le script HubSpot est déjà chargé
  var hubspotFormsV4 = copyFromWindow('HubspotFormsV4');
  
  if (!hubspotFormsV4) {
    // Définir une fonction qui sera appelée lorsque HubspotFormsV4 sera disponible
    var checkForHubspotFormsV4 = function() {
      var hubspotFormsV4 = copyFromWindow('HubspotFormsV4');
      if (hubspotFormsV4) {
        // Supprimer l'intervalle une fois que HubspotFormsV4 est disponible
        var interval = copyFromWindow('_hsFormsV4Interval');
        if (interval) {
          callInWindow('clearInterval', interval);
        }
        
        // Configurer l'écouteur d'événements
        setupV4EventListener();
      }
    };
    
    // Vérifier périodiquement si HubspotFormsV4 est disponible
    var intervalId = callInWindow('setInterval', checkForHubspotFormsV4, 500);
    setInWindow('_hsFormsV4Interval', intervalId);
  } else {
    // HubspotFormsV4 est déjà disponible, configurer l'écouteur d'événements
    setupV4EventListener();
  }
  
  onSuccess();
};

var setupV4EventListener = function() {
  var listener = function(event) {
    var hubspotFormsV4 = copyFromWindow('HubspotFormsV4');
    if (!hubspotFormsV4) return;
    
    callInWindow('HubspotFormsV4.getFormFromEvent', event, function(form) {
      if (!form) return;
      
      var formData = {
        event: eventName + '-v4',
        'hs-form-id': callInWindow('form.getFormId')
      };
      
      if (includeFormData) {
        callInWindow('form.getFormFieldValues', function(values) {
          if (values && values.length) {
            for (var i = 0; i < values.length; i++) {
              var field = values[i];
              var key = 'hs-' + cleanFieldName(field.name);
              formData[key] = field.value;
            }
          }
          dataLayerPush(formData);
        });
      } else {
        dataLayerPush(formData);
      }
    });
  };
  
  // Ajouter l'écouteur d'événements pour les formulaires v4
  callInWindow('addEventListener', 'hs-form-event:on-submission:success', listener);
};

// --- Script pour les formulaires V3 ---
var setupV3Listener = function() {
  var v3ScriptStr = '' +
    '(function() {' +
    '  var addEventListener = function(eventName, callback) {' +
    '    if (document.addEventListener) {' +
    '      document.addEventListener(eventName, callback);' +
    '    } else {' +
    '      document.attachEvent("on" + eventName, callback);' +
    '    }' +
    '  };' +
    '  addEventListener("message", function(event) {' +
    '    if (event.data && event.data.type === "hsFormCallback" && ' +
    '        (event.data.eventName === "onFormSubmitted" || event.data.eventName === "onFormSubmit")) {' +
    '      var formData = {' +
    '        event: "' + eventName + '-v3",' +
    '        "hs-form-guid": event.data.id' +
    '      };' +
    '      ' +
    '      if (event.data.data && event.data.data.submissionValues && ' + includeFormData + ') {' +
    '        for (var field in event.data.data.submissionValues) {' +
    '          if (event.data.data.submissionValues.hasOwnProperty(field)) {' +
    '            var cleanedField = "";' +
    '            for (var i = 0; i < field.length; i++) {' +
    '              var char = field.charAt(i);' +
    '              if ((char >= "a" && char <= "z") || ' +
    '                  (char >= "A" && char <= "Z") || ' +
    '                  (char >= "0" && char <= "9") || ' +
    '                  char === "_") {' +
    '                cleanedField += char;' +
    '              } else {' +
    '                cleanedField += "_";' +
    '              }' +
    '            }' +
    '            var key = "hs-" + cleanedField;' +
    '            formData[key] = event.data.data.submissionValues[field];' +
    '          }' +
    '        }' +
    '      }' +
    '      ' +
    '      window.dataLayer = window.dataLayer || [];' +
    '      window.dataLayer.push(formData);' +
    '    }' +
    '  });' +
    '})();';
  
  // Injecter le script
  injectScript(v3ScriptStr, onSuccess, onFailure, 'hubspot_v3_listener');
};

// --- Logique de sélection ---
if (formType === 'form_v3') {
  setupV3Listener();
} else if (formType === 'form_v4') {
  setupV4Listener();
} else if (formType === 'form_both') {
  setupV3Listener();
  setupV4Listener();
} else {
  onFailure('Valeur de formType inconnue : ' + formType);
}


___WEB_PERMISSIONS___

[
  {
    "instance": {
      "key": {
        "publicId": "access_globals",
        "versionId": "1"
      },
      "param": [
        {
          "key": "keys",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "key"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  },
                  {
                    "type": 1,
                    "string": "execute"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "dataLayer"
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": true
                  }
                ]
              }
            ]
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "logging",
        "versionId": "1"
      },
      "param": [
        {
          "key": "environments",
          "value": {
            "type": 1,
            "string": "debug"
          }
        }
      ]
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "inject_script",
        "versionId": "1"
      },
      "param": [
        {
          "key": "urls",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "https://*.hubspot.com/*"
              },
              {
                "type": 1,
                "string": "https://*.hs-scripts.com/*"
              }
            ]
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  }
]


___TESTS___

scenarios: []


___NOTES___

Created on 09/04/2025 09:50:21


