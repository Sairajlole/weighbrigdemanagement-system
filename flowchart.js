```jsx
"step_01_retryQueueExecution": {
"description": "Before starting weighment, retry any failed tasks.",
"queues": ["PrintQueue", "SheetsQueue", "DriveQueue", "WhatsAppQueue", "StickerQueue", "BillingQueue"],
"queueConfigs": {
"PrintQueue": {
"maxRetries": 3,
"retryIntervalSec": 60,
"lastRetryTime": null,
"retryCount": 0
},
"SheetsQueue": {
"maxRetries": 3,
"retryIntervalSec": 60,
"lastRetryTime": null,
"retryCount": 0
},
"DriveQueue": {
"maxRetries": 3,
"retryIntervalSec": 60,
"lastRetryTime": null,
"retryCount": 0
},
"WhatsAppQueue": {
"maxRetries": 3,
"retryIntervalSec": 60,
"lastRetryTime": null,
"retryCount": 0
},
"StickerQueue": {
"maxRetries": 3,
"retryIntervalSec": 60,
"lastRetryTime": null,
"retryCount": 0
},
"BillingQueue": {
"maxRetries": 3,
"retryIntervalSec": 60,
"lastRetryTime": null,
"retryCount": 0
}
},
"actions": {
"ifSuccess": "Remove from queue and log success",
"ifFail": {
"incrementRetryCount": true,
"ifRetryCountExceedsLimit": "Log failure, alert admin",
"else": "Retain in queue for next retry cycle"
}
}
}
```

    ```jsx
"step_02_operatorVerification": {
"description": "Verifies the identity of the operator before weighment begins.",
"verificationMode": "AUTO",  // PHOTO_MATCH or BIOMETRIC (only one enabled at a time)
"allowedModes": ["PHOTO_MATCH", "BIOMETRIC", "USER_PASS"],
"photoMatch": {
"enabled": true,
"cameraId": "CAM_OPERATOR",
"timeoutSec": 8,
"maxAttempts": 5,
"onFail": {
"fallbackTo": "USER_PASS",
"logFailedAttempt": true,
"captureImage": true
}
},
"biometric": {
"enabled": false,
"deviceId": "BIO_DEVICE_1",
"maxAttempts": 5,
"onFail": {
"fallbackTo": "USER_PASS",
"logFailedAttempt": true,
"captureScanData": true
}
},
"userPass": {
"enabled": true,
"promptUI": true,
"maxAttempts": null,
"infiniteRetry": true,
"validateAgainstOperatorDB": true
},
"onSuccess": {
"setOperatorVerified": true,
"bindOperatorId": true
},
"logVerificationAttempts": true
}
```

    ```jsx
"step_03_rfidDetection": {
"enabled": true,
"scanTimeoutSec": 10,  // Time to wait before considering RFID scan failed
"retryIntervalSec": 2,  // Interval between scan attempts
"onDetection": "Open entry gate",
"onTimeout": {
"fallbackToManual": true,
"requireOperatorVerification": true,
"logTimeoutEvent": true
},
"ifDisabled": {
"manualTrigger": true,
"requireOperatorVerification": true
}
}
```

    ```jsx
"step_04_weightCheckBeforeEntry": {
"requireLiveWeightToBeZero": true,
"onNotZero": {
"message": "Clear weighbridge before entry",
"abortWeighment": true,
"retryAllowed": true,
"maxRetries": null,
"adminOverrideAllowed": true,
"overrideRequiresPin": true
}
}
```

    ```jsx
"step_05_vehicleEntry": {
"openGate": true,
"waitForVehicleSensor": true
}
```

    ```jsx
"step_06_stabilization": {
"description": "Ensure vehicle has fully entered the weighbridge using all configured methods before locking gates.",
"confirmationMethodsRequired": ["IR", "Weight", "Camera"],  // All listed must pass
"irConfig": {
"enabled": true,
"sensorIds": ["IR_FRONT", "IR_REAR"],
"minDurationSec": 2,
"timeoutSec": 10
},
"weightConfig": {
"enabled": true,
"minWeightKg": 1000,
"stabilizeWindowSec": 5,
"timeoutSec": 15
},
"cameraBoundaryCheck": {
"enabled": true,
"useAllCamerasWithPurpose": [
"PlatformLeftView",
"PlatformRightView",
"PlatformTopView",
"PlatformRearView",
"PlatformFrontView"
],
"method": "boundaryBoxInsidePlatform",
"timeoutSec": 12,
"onFail": {
"retryAllowed": true,
"maxRetries": null,
"fallbackTo": null,
"logFailure": true
}
},
"onConfirmed": {
"closeEntryGate": true,
"lockAllGates": true
},
"onTimeout": {
"adminOverrideAllowed": true,
"overrideRequiresPin": true,
"retryAllowed": true,
"maxRetries": null
},
"logStabilizationEvent": true
}
```

    ```jsx
"step_08_cctvDetection": {
"description": "Use cameras to detect vehicle number plate and driver face before weighment.",
"vehicleNumberPlate": {
"enabled": true,
"useAllCamerasWithPurpose": true,  // All cameras with purpose: VehicleNumberPlate
"minConfidence": 0.85,
"saveDetectionMetadata": true,
"onFail": {
"retryAllowed": true,
"maxRetries": null,
"fallbackTo": "ManualInputIfOperatorVerified",
"logFailure": true
},
"onConflict": {
"adminReviewOnConflict": true  // If multiple plates detected, allow operator selection
"driverFace": {
"enabled": true,
"useAllCamerasWithPurpose": true,  // All cameras with purpose: DriverFace
"minConfidence": 0.85,
"saveDetectionMetadata": true,
"faceMatchWithPreviousRecord": {
"enabled": true,
"minMatchScore": 0.8,
"onMismatch": {
"allowManualConfirmation": true,
"logMismatch": true
}
},
"onFail": {
"retryAllowed": true,
"maxRetries": null,
"fallbackTo": "ForceIfOperatorVerified",
"logFailure": true
},
"onConflict": {
"adminReviewOnConflict": true  // If multiple faces detected
}
}
}
}
},
```

    ```jsx
"step_09_driverAssist": {
"description": "Ensure only the driver is present on the weighbridge platform. Uses all cameras except for CustomerFace and OperatorFace.",
"enabled": true,  // Set to false to disable this step
"useAllCamerasExceptPurpose": [
"CustomerFace",
"OperatorFace"
],
"expectedFaces": {
"min": 1,
"max": 1
},
"pollIntervalSec": 1,
"timeoutSec": 15,
"logOnFaceCountMismatch": true,
"saveSnapshotOnMismatch": true,
"onMismatch": {
"alertOperator": true,
"retryAllowed": true,
"maxRetries": null,
"adminOverrideAllowed": true,
"overrideRequiresPin": true,
"forceIfOperatorVerified": true
},
"onDisabled": {
"logBypass": true,
"allowManualTriggerFromAdmin": true  // Admin can trigger this logic manually via dashboard
}
}
```

    ```jsx
"step_10_materialRecognition": {
"description": "Automatically detect the material loaded in the vehicle using all available platform-related cameras, excluding customer/operator face cameras.",
"enabled": true,
"useAllCamerasExceptPurpose": [
"CustomerFace",
"OperatorFace"
],
"minConfidence": 0.8,
"onRecognitionSuccess": {
"material": "Predicted",
"confidence": "Score",
"savePredictionSnapshot": true,
"logPredictionMetadata": true,
"confirmBeforeLocking": true  // Let admin/operator confirm material before finalizing
},
"onRecognitionFail": {
"promptManualInput": true,
"logFailure": true
},
"onCoveredVehicle": {
"status": "covered",
"fallback": "Manual input",
"logCoveredStatus": true
},
"onDisabled": {
"logBypass": true,
"allowManualInput": true
}
}
```

    ```jsx
"step_11_customerVerification": {
"description": "Identify and verify the customer using facial recognition and phone number. Fetch from or register into customer database.",
"enabled": true,
// Step 1: Face recognition using all CustomerFace cameras
"faceRecognition": {
"enabled": true,
"useAllCamerasWithPurpose": ["CustomerFace"],

// AI model settings
"minConfidence": 0.85,
"matchWithExistingCustomerDB": true,

// If a match is found
"onMatch": {
  "autoFillCustomerDetails": true,  // Fetch name, phone, address
  "bindToSession": true             // Attach to current weighment
},

// If no match is found
"onNoMatch": {
  "promptPhoneInput": true,
  "allowNewCustomerRegistration": true,
  "logAsUnidentified": true
},

// If face detection fails (e.g. camera can't detect a face)
"onFail": {
  "retryAllowed": true,
  "maxRetries": null,  // infinite
  "logFailedFaceMatch": true,
  "saveSnapshotOnFail": true,
  "skipIfOperatorVerified": true
}
},
// Step 2: Phone number verification and linking
"phonePrompt": {
"enabled": true,
"requiredLength": 10,
"showMaskedIfPreFetched": true,  // If matched, show masked phone: XXXXX1234
"allowEdit": true,               // Operator can edit if mismatch
"validateFormat": "^[6-9][0-9]{9}$",  // Regex pattern for 10-digit Indian number
// Cross-check phone input with face-linked data if available
"phoneFaceCrossValidation": {
  "enabled": true,
  "minMatchConfidence": 0.85,
  "onMismatch": {
    "logMismatch": true,
    "allowManualOverride": true,
    "retryAllowed": true,
    "fallbackToManualEntry": true
  }
}
},
// Step 3: New customer flow
"newCustomerEntry": {
"enabled": true,
"namePrompt": {
"enabled": true,
"format": "TitleCase",
"minWords": 2
},
"addressPrompt": {
"enabled": true,
"format": "TitleCase",
"allowDropdownWithTyping": true
},
"saveToDatabase": true,
"assignUniqueCustomerId": true,
"attachToWeighmentSession": true
},
// Optional manual override
"manualOverride": {
"enabled": true,
"allowedRoles": ["admin", "support"],
"requiresPin": true,
"logOverrideAction": true
},
// If this step is disabled globally
"onDisabled": {
"logBypass": true,
"allowManualEntry": {
"name": true,
"phone": true,
"address": true
},
"attachManuallyEnteredDataToSession": true
}
}
```

    ```jsx
"step_12_rstManagement": {
"description": "Manage RST (Receipt Serial Ticket) numbers for each weighment. Ensure uniqueness, cloud/local fallback, and session safety.",
// Step enabled
"enabled": true,
// Prefetch and pool logic
"prefetchStrategy": {
"enabled": true,
"minPoolSize": 5,
"batchRequestSize": 20,
"autoAdjustBasedOnUsage": true,  // Analyzes past 7-day usage average to adjust pool size dynamically
"checkIntervalMinutes": 30       // Re-evaluate pool refill every 30 minutes
},
// RST format configuration
"rstFormat": {
"type": "numeric",               // Can be: numeric, alphanumeric, prefixed
"startFrom": 1,
"maxLength": 6,
"prefix": "",                    // e.g., "RST-" or "" (empty)
"allowLeadingZeros": false,
"paddingChar": null              // Optional: pad with a character like "0" if needed
},
// Source selection and fallback rules
"sourcePriority": ["cloud", "local"],
"cloudSource": {
"enabled": true,
"apiEndpoint": "/rst/request-batch",
"authRequired": true,
"retryOnFail": true,
"logPullAttempts": true
},
"localFallback": {
"enabled": true,
"maxOfflineBuffer": 100,
"path": "local/cache/rst_pool.json"
},
"abortIfNoneAvailable": true,
// Locking, validation and tracking
"lockAssignedRST": true,
"preventReuse": true,
"trackUsageHistory": true,
"usageLog": {
"enabled": true,
"fields": ["rstNumber", "timestamp", "assignedToSessionId", "operatorId", "deviceId"]
},
// Recovery after crash or incomplete session
"recoveryOnCrash": {
"enabled": true,
"retainLastAssignedIfIncomplete": true,
"logRecoveredRST": true,
"forceOperatorValidation": true
}
}
```

    ```jsx
"step_13_saveWeighment": {
"description": "Save all weighment details including weights, timestamps, camera snapshots, customer/operator info, and auto-assign metadata.",
"enabled": true,
"fieldValidation": {
"validateAgainstConfiguredFields": true,
"requiredFieldsByType": {
"system": ["rstNumber", "sessionId", "deviceId", "weighbridgeId"],
"vehicle": ["vehicleNumber"],
"customer": ["customerName", "customerPhone", "customerAddress"],
"material": ["material"],
"weight": ["grossWeight", "tareWeight", "netWeight"],
"timestamp": ["grossDateTime", "tareDateTime"],
"operator": ["operatorId", "operatorName", "operatorRole"],
"security": ["ipAddress"],
"camera": ["driverFaceSnapshot", "vehicleEntrySnapshot", "platformViewSnapshot"]
},
"allowSaveOnlyIfAllPresent": true,
"logValidationFailures": true
},
"autoBindMetadata": {
"sessionId": true,
"deviceId": true,
"ipAddress": true,
"operatorRole": true,
"weighbridgeId": true
},
"cameraSnapshots": {
"storeToPath": "local/yyyy/mm/dd/sessionId/",
"structure": {
"VEHICLE_ENTRY": ["entry1.jpg", "entry2.jpg"],
"VEHICLE_EXIT": ["exit1.jpg", "exit2.jpg"],
"DRIVER_FACE": "driver.jpg",
"CUSTOMER_FACE": "customer.jpg",
"OPERATOR_IMAGE": "operator.jpg",
"PLATFORM_ENTRY": ["platform_left.jpg", "platform_right.jpg"],
"PLATFORM_EXIT": ["platform_exit_left.jpg", "platform_exit_right.jpg"]
},
"logSnapshotPaths": true,
"attachToWeighmentRecord": true
},
"autoBackup": {
"enabled": true,
"beforeSavePath": "local/recovery/before/yyyy-mm-dd/",
"afterSavePath": "local/recovery/after/yyyy-mm-dd/",
"includeSnapshots": true,
"includeMetadata": true
},
"sessionFinalization": {
"markCompleted": true,
"allowEditAfterSave": false,
"adminOverrideRequiredToEdit": true,
"logEditAttempts": true
}
}
```

    ```jsx
"step_14_pdfGeneration": {
"description": "Generate a formatted PDF receipt (RST slip) using a configurable template system. Supports DotMatrix and Google Slides engines with placeholders, formatting, and branding.",
"enabled": true,
// Supported engines
"templateType": ["GoogleSlides", "DotMatrix"],
"defaultTemplateType": "GoogleSlides",
// Template selector
"templates": [
{
"templateId": "default_template",
"templateName": "Standard RST Format",
"templateEngine": "GoogleSlides",
"variant": "backgroundOnly",  // backgroundOnly or fullCustom
"isDefault": true
},
{
"templateId": "compact_mobile",
"templateName": "Compact Mobile Print",
"templateEngine": "DotMatrix",
"variant": "compact",
"isDefault": false
}
],
// Placeholder system
"templatePlaceholders": {
"enabled": true,
"configurableByAdmin": true,
"defaultPlaceholders": [
"{{RST_NUMBER}}",
"{{CUSTOMER_NAME}}",
"{{CUSTOMER_PHONE}}",
"{{CUSTOMER_ADDRESS}}",
"{{VEHICLE_NUMBER}}",
"{{MATERIAL}}",
"{{WEIGHT_GROSS}}",
"{{WEIGHT_TARE}}",
"{{WEIGHT_NET}}",
"{{GROSS_DATE}}",
"{{TARE_DATE}}",
"{{GROSS_TIME}}",
"{{TARE_TIME}}",
"{{OPERATOR_NAME}}",
"{{DEVICE_ID}}",
"{{COMPANY_NAME}}",
"{{COMPANY_ADDRESS}}",
"{{COMPANY_EMAIL}}",
"{{COMPANY_GSTIN}}",
"{{COMPANY_LOGO}}"
],
"alignmentOptions": ["left", "center", "right"],
"multiPlaceholderRowSupport": {
"enabled": true,
"layoutRules": {
"maxColumns": 4,
"evenSpacing": true,
"columnAlignment": "flex-distribute"
}
}
},
// Versioning of output files
"versioning": {
"enabled": true,
"appendVersionToFilename": true
},
// Branding (Slides only — logo placeholder only)
"branding": {
"enabled": true,
"appliesTo": "GoogleSlidesOnly",
"placeholders": {
"logo": "{{COMPANY_LOGO}}"
},
"allowLogoPlaceholder": true,
"logoFile": {
"uploadPath": "assets/branding/logo.png",
"maxSizeMB": 2,
"formatsAllowed": ["png", "jpg", "jpeg"],
"recommendedAspectRatio": "4:1"
}
},
// Layout formatting
"layoutSettings": {
"dynamicMargin": true,  // Leave minimal clean space around content
"maxContentWidthPercent": 90,
"font": "Roboto",
"fontSizePt": 10,
"lineSpacing": 1.2,
"textWrap": true,
"alignment": "left"
},
// Output paths
"outputPaths": {
"local": "local/yyyy/mm/dd/rst_{{RST_NUMBER}}v{{VERSION}}.pdf",
"drive": "drive/yyyy/mm/dd/rst{{RST_NUMBER}}_v{{VERSION}}.pdf"
},
// Google Slides modes
"googleSlidesMode": {
"variant": ["backgroundOnly", "fullCustom"],
"backgroundOnly": {
  "description": "Admin uploads background image. Text and placeholders are auto-placed using DotMatrix template logic.",
  "allowedPlaceholders": "All from dotMatrix config",
  "textFormatEnforced": true
},

"fullCustom": {
  "description": "Admin provides a full Google Slides template with placeholders like {{RST_NUMBER}} directly embedded.",
  "allowedPlaceholders": "All default placeholders",
  "textFormatFromSlide": true
}
},
// Error handling
"onFail": {
"addToQueue": "DriveQueue",
"logError": true,
"retryAllowed": true,
"retryLimit": 3
}
}
```

    ```jsx
"step_15_printing": {
  "description": "Print the RST slip using the active DotMatrix template if a dot matrix printer is available. Fallback to Google Slides or selected template using a normal printer. Supports preview, auto-print, and printer-specific settings.",

  "enabled": true,

  // Dot Matrix Printing
  "dotMatrix": {
    "enabled": true,
    "defaultPrinterDetection": true,
    "templatePreviewMode": true,
    "useEnabledTemplateOnly": true,

    // Link to active DotMatrix template (from admin-selected templates)
    "templateSource": {
      "templateType": "DotMatrix",
      "source": "templatePreview.activeTemplateId"
    },

    // Apply printer-specific supported options only
    "capabilityAwareOptions": {
      "showOnlySupported": true,

      "detectableProperties": {
        "supportedPaperWidths": [10, 12],               // in inches
        "supportedFontSizesCPI": [10, 12, 15],
        "supportedLineSpacings": [1.0, 1.5, 2.0],
        "supportsDoubleHeightLines": true,
        "supportsBoldText": true,
        "supportsUnderline": false,
        "maxCharsPerLine": 120
      },

      "uiOptions": {
        "paperWidthInches": {
          "type": "dropdown",
          "optionsFrom": "supportedPaperWidths"
        },
        "fontSizeCPI": {
          "type": "dropdown",
          "optionsFrom": "supportedFontSizesCPI"
        },
        "lineSpacing": {
          "type": "dropdown",
          "optionsFrom": "supportedLineSpacings"
        },
        "doubleHeightText": {
          "type": "toggle",
          "enabledIf": "supportsDoubleHeightLines"
        },
        "boldText": {
          "type": "toggle",
          "enabledIf": "supportsBoldText"
        },
        "underline": {
          "type": "toggle",
          "enabledIf": "supportsUnderline"
        }
      }
    },

    "activeSettings": {
      "paperWidthInches": 12,
      "fontSizeCPI": 12,
      "lineSpacing": 1.0,
      "doubleHeightText": false,
      "boldText": true,
      "underline": false
    }
  },

  // Fallback to regular printer if dot matrix not available
  "fallbackPrinter": {
    "enabled": true,
    "autoDetectAvailablePrinters": true,
    "promptUserToSelect": true,
    "templateOptions": {
      "availableTypes": ["GoogleSlides", "DotMatrix"],
      "defaultType": "GoogleSlides"
    }
  },

  // Auto-print after successful weighment save
  "autoPrintAfterSave": {
    "enabled": true,
    "defaultCopies": 1,
    "allowEditCopies": true,
    "maxCopies": 5,
    "allowDisablePerUser": true
  },

  // Print Preview and Confirmation
  "printPreview": {
    "enabled": true,
    "requireOperatorConfirmation": true
  },

  // Reprint logic with control
  "reprintPolicy": {
    "enabled": true,
    "maxReprints": 2,
    "allowedRoles": ["admin", "support"],
    "logEveryReprint": true,
    "promptBeforeReprint": true
  },

  // Failure Handling and Retry
  "onFail": {
    "logFailure": true,
    "addToQueue": "PrintQueue",
    "retryAllowed": true,
    "retryLimit": 2
  }
}
```

    ```jsx
"step_16_stickerPrint": {
  "description": "Print a horizontally oriented sticker (printed vertically) with a full-height PDF417 barcode on the left and up to 6 user-selected placeholders arranged in a 3×2 layout. Layout adapts if fewer placeholders are used.",

  "enabled": true,

  "trigger": {
    "mode": ["auto", "manual"],
    "defaultMode": "auto",
    "triggerPoint": "afterWeighmentSave"
  },

  "copies": {
    "default": 1,
    "editableByOperator": true,
    "noCopyLimit": true
  },

  "paper": {
    "orientation": "horizontal",
    "printDirection": "vertical",
    "paperWidthMM": 58,
    "marginMM": {
      "top": 5,
      "bottom": 5,
      "left": 5,
      "right": 5
    }
  },

  "barcode": {
    "type": "PDF417",
    "contentFormat": "structuredData",
    "dataSource": "dotMatrix.enabledPlaceholders",
    "includeHeaderLabel": true,
    "height": "full",
    "widthPercent": 35,
    "paddingRightMM": 3
  },

  "contentLayout": {
    "type": "dynamicGrid",
    "maxPlaceholders": 6,
    "placeholderSource": "stickerPrint.visiblePlaceholders",
    "layoutRules": {
      "rows": 3,
      "columns": 2,
      "autoAdjustForLess": true,
      "labelValueSeparator": ":",
      "horizontalAlignment": "even",
      "equalSpacingLeftRight": true,
      "verticalSpacingMM": 4
    },
    "textStyle": {
      "fontSizePt": 9,
      "bold": false,
      "uppercase": false,
      "wrapText": false
    }
  },

  "placeholderConfig": {
    "adminCanEnableDisable": true,
    "availablePlaceholders": [
      "{{WEIGHT_GROSS_DATE}}",
      "{{RST_NUMBER}}",
      "{{CUSTOMER_NAME}}",
      "{{CUSTOMER_ADDRESS}}",
      "{{MATERIAL}}",
      "{{WEIGHT_NET}}",
      "{{CUSTOMER_PHONE}}",
      "{{VEHICLE_NUMBER}}",
      "{{OPERATOR_NAME}}",
      "{{GROSS_TIME}}",
      "{{TARE_TIME}}"
    ],
    "visiblePlaceholders": [
      "{{WEIGHT_GROSS_DATE}}",
      "{{RST_NUMBER}}",
      "{{CUSTOMER_NAME}}",
      "{{CUSTOMER_ADDRESS}}",
      "{{MATERIAL}}",
      "{{WEIGHT_NET}}"
    ],
    "maxAllowed": 6
  },

  "onFail": {
    "addToQueue": "StickerQueue",
    "logError": true,
    "retryAllowed": true,
    "retryLimit": 2
  }
}
```

    ```jsx
"step_17_googleSheetsSync": {
  "description": "Sync only the enabled Dot Matrix placeholders to Google Sheets after weighment. Keeps Google Sheet output consistent with printed fields.",

  "enabled": true,

  "sheetName": "RST Database",
  "targetTab": "Weighments",

  "fieldsSynced": {
    "source": "dotMatrix.enabledPlaceholders"
  },

  "formatting": {
    "autoFormatHeaders": true,
    "timestampFormat": "dd-MM-yyyy HH:mm:ss",
    "weightColumns": ["GROSS_WEIGHT", "TARE_WEIGHT", "NET_WEIGHT"],
    "textCase": {
      "CUSTOMER_NAME": "title",
      "CUSTOMER_ADDRESS": "title",
      "MATERIAL": "uppercase",
      "OPERATOR_NAME": "title"
    }
  },

  "syncTrigger": {
    "onSaveWeighment": true,
    "retryOnFail": true,
    "retryDelaySec": 15,
    "maxRetries": 5
  },

  "onFail": {
    "addToQueue": "SheetsQueue",
    "logError": true,
    "notifyOperator": false
  },

  "ensureSheetExists": true,
  "insertAtTop": false,
  "deduplicateByRST": true
}
```

    ```jsx
"step_18_whatsapp": {
  "description": "Send WhatsApp message with placeholders and PDF attachment after weighment. Uses placeholders from Dot Matrix template and supports retries on failure.",

  "enabled": true,

  // Message template with dynamic placeholders
  "messageTemplate": "Hello {{CUSTOMER_NAME}}, your vehicle {{VEHICLE_NUMBER}} has been weighed. Net Weight: {{WEIGHT_NET}} kg | RST No: {{RST_NUMBER}}.",

  // Source for available placeholders (same as Dot Matrix)
  "placeholdersSource": "dotMatrix.enabledPlaceholders",

  // PDF attachment settings
  "attachPDF": true,
  "pdfPathSource": "PDF_PATH",
  "pdfNameFormat": "RST_{{RST_NUMBER}}.pdf",

  // Optional image previews (not used currently)
  "attachImages": false,
  "imagesSource": [
    "CAM_VEHICLE_ENTRY", 
    "CAM_PLATFORM", 
    "CAM_DRIVER"
  ],

  // Fallback and retry logic
  "onFail": {
    "addToQueue": "WhatsAppQueue",
    "retryAllowed": true,
    "retryDelaySec": 30,
    "maxRetries": 3,
    "logFailure": true
  },

  // WhatsApp API integration
  "provider": {
    "name": "WhatsAppBusinessAPI",
    "authToken": "<AUTH_TOKEN>",
    "endpoint": "https://api.provider.com/sendMessage",
    "method": "POST",
    "headers": {
      "Content-Type": "application/json",
      "Authorization": "Bearer <AUTH_TOKEN>"
    },
    "payloadFormat": {
      "phone": "{{CUSTOMER_PHONE}}",
      "message": "{{COMPILED_MESSAGE}}",
      "fileUrl": "{{PDF_PATH}}"
    }
  }
}
```

    ```jsx
"step_19_billingSync": {
  "description": "Sync weighment data, receipt PDF, barcode, and all camera snapshots with billing system immediately after weighment. Retry if failed.",

  "enabled": true,

  // When to trigger billing sync
  "trigger": {
    "onSaveWeighment": true
  },

  // What protocol to use
  "protocol": "REST",

  // Data sent to billing module
  "fieldsSynced": {
    "placeholdersSource": "dotMatrix.enabledPlaceholders",  // Same fields shown in print
    "attachments": {
      "pdf": "{{PDF_PATH}}",
      "barcodeData": "{{BARCODE_DATA}}",
      "cameraSnapshots": {
        "vehicleEntry": ["entry1.jpg", "entry2.jpg"],
        "vehicleExit": ["exit1.jpg", "exit2.jpg"],
        "platformEntry": ["platform_left.jpg", "platform_right.jpg"],
        "platformExit": ["platform_exit_left.jpg", "platform_exit_right.jpg"],
        "driverFace": "driver.jpg",
        "customerFace": "customer.jpg",
        "operator": "operator.jpg"
      }
    }
  },

  // Integration with billing server
  "billingAPI": {
    "endpoint": "https://billing.example.com/api/syncWeighment",
    "method": "POST",
    "headers": {
      "Content-Type": "application/json",
      "Authorization": "Bearer <API_TOKEN>"
    },
    "payloadFormat": {
      "placeholders": "{{COMPILED_PLACEHOLDERS}}",
      "pdfUrl": "{{PDF_PATH}}",
      "barcode": "{{BARCODE_DATA}}",
      "images": {
        "vehicleEntry": ["{{entry1.jpg}}", "{{entry2.jpg}}"],
        "vehicleExit": ["{{exit1.jpg}}", "{{exit2.jpg}}"],
        "platformEntry": ["{{platform_left.jpg}}", "{{platform_right.jpg}}"],
        "platformExit": ["{{platform_exit_left.jpg}}", "{{platform_exit_right.jpg}}"],
        "driverFace": "{{driver.jpg}}",
        "customerFace": "{{customer.jpg}}",
        "operator": "{{operator.jpg}}"
      }
    }
  },

  // Failure handling
  "onFail": {
    "addToQueue": "BillingQueue",
    "retryAllowed": true,
    "retryDelaySec": 30,
    "maxRetries": 5,
    "logFailure": true
  }
}
```

    ```jsx
"step_20_exitSequence": {
  "description": "Handles vehicle exit process after successful weighment, including gate control, session clearing, and operator flag reset.",

  "enabled": true,

  // Exit gate operations
  "exitGateControl": {
    "openExitGate": true,
    "waitForVehicleExitSensor": true,
    "closeGateAfterExit": true,
    "maxWaitTimeoutSec": 60
  },

  // Session cleanup
  "sessionReset": {
    "resetFlags": [
      "operatorVerified",
      "vehicleInProgress",
      "camerasInUse",
      "weightStabilized"
    ],
    "clearTemporaryCache": true,
    "clearSessionData": true
  },

  // Visual or audio confirmation to operator
  "confirmationToOperator": {
    "showToast": "Weighment complete. Exit gate opened.",
    "playBeep": true,
    "logCompletion": true
  },

  // Optional LED/Display message
  "displayBoard": {
    "enabled": true,
    "message": "THANK YOU | EXIT NOW",
    "durationSec": 8
  },

  // Log final step
  "logging": {
    "recordExitTimestamp": true,
    "recordFinalWeightState": true,
    "saveExitLogEntry": true
  }
}
```