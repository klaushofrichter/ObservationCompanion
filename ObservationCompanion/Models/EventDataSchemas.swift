import Foundation

/// Mapping of EEN event types to their supported data schemas.
/// Ported from the TypeScript toolkit's `dataSchemas.ts`.
/// Used to dynamically build the `include` parameter when fetching events.
enum EventDataSchemas {

    /// Data schemas keyed by event type.
    static let schemas: [String: [String]] = [
        // Detection events
        "een.motionDetectionEvent.v1": [
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.motionInRegionDetectionEvent.v1": [
            "een.motionRegion.v1",
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.personDetectionEvent.v1": [
            "een.objectDetection.v1",
            "een.personAttributes.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.objectClassification.v1",
            "een.objectRegionMapping.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
            "een.geoLocation.v1",
        ],
        "een.personMotionDetectionEvent.v1": [
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.objectClassification.v1",
        ],
        "een.animalDetectionEvent.v1": [
            "een.objectDetection.v1",
            "een.animalAttributes.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.objectClassification.v1",
            "een.objectRegionMapping.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.faceDetectionEvent.v1": [
            "een.objectDetection.v1",
            "een.personAttributes.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.objectClassification.v1",
            "een.objectRegionMapping.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.vehicleDetectionEvent.v1": [
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.objectClassification.v1",
            "een.vehicleAttributes.v1",
            "een.objectRegionMapping.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.vehicleMotionDetectionEvent.v1": [
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.objectClassification.v1",
            "een.vehicleAttributes.v1",
        ],
        "een.gunDetectionEvent.v1": [
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.objectDetection.v1",
            "een.motionRegion.v1",
            "een.objectClassification.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
            "een.weaponAttributes.v1",
            "een.personAttributes.v1",
            "een.humanValidationDetails.v1",
        ],
        "een.weaponDetectionEvent.v1": [
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.objectDetection.v1",
            "een.motionRegion.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.fallDetectionEvent.v1": [
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.fireDetectionEvent.v1": [
            "een.objectDetection.v1",
            "een.objectClassification.v1",
            "een.croppedFrameImageUrl.v1",
            "een.fullFrameImageUrl.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.spillDetectionEvent.v1": [
            "een.objectDetection.v1",
            "een.objectClassification.v1",
            "een.croppedFrameImageUrl.v1",
            "een.fullFrameImageUrl.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.crowdFormationDetectionEvent.v1": [
            "een.objectDetection.v1",
            "een.objectClassification.v1",
            "een.croppedFrameImageUrl.v1",
            "een.fullFrameImageUrl.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],

        // Camera analytics events
        "een.tamperDetectionEvent.v1": [
            "een.fullFrameImageUrl.v1",
        ],
        "een.loiterDetectionEvent.v1": [
            "een.loiterArea.v1",
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.objectLineCrossEvent.v1": [
            "een.lineCrossLine.v1",
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.entryDirection.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.objectLineCrossCountEvent.v1": [
            "een.lineCrossLine.v1",
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.entryDirection.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.countedObjectLineCrossEvent.v1": [
            "een.countedLineCross.v1",
        ],
        "een.objectIntrusionEvent.v1": [
            "een.intrusionArea.v1",
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.entryDirection.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.objectRemovalEvent.v1": [
            "een.monitoredArea.v1",
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.personTailgateEvent.v1": [
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.ppeViolationEvent.v1": [
            "een.objectDetection.v1",
            "een.personAttributes.v1",
            "een.fullFrameImageUrl.v1",
            "een.croppedFrameImageUrl.v1",
            "een.objectClassification.v1",
            "een.objectRegionMapping.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],

        // AI/Scene events
        "een.sceneLabelEvent.v1": [
            "een.objectDetection.v1",
            "een.objectClassification.v1",
            "een.vehicleAttributes.v1",
            "een.personAttributes.v1",
            "een.animalAttributes.v1",
            "een.croppedFrameImageUrl.v1",
            "een.fullFrameImageUrl.v1",
            "een.objectRegionMapping.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.customLabels.v1",
            "een.eevaAttributes.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
        ],
        "een.eevaQueryEvent.v1": [
            "een.customLabels.v1",
            "een.eevaAttributes.v1",
            "een.objectDetection.v1",
            "een.fullFrameImageUrl.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
            "een.displayOverlay.boundingBox.v1",
        ],

        // License plate and fleet recognition
        "een.lprPlateReadEvent.v1": [
            "een.objectDetection.v1",
            "een.lprDetection.v1",
            "een.vehicleAttributes.v1",
            "een.lprAccessType.v1",
            "een.userData.v1",
            "een.userTags.v1",
            "een.croppedFrameImageUrl.v1",
            "een.fullFrameImageUrl.v1",
            "een.displayOverlay.boundingBox.v1",
            "een.fullFrameImageUrlWithOverlay.v1",
            "een.vehicleListInfo.v1",
            "een.resourceDetails.v1",
            "een.vspInsightsSummary.v1",
        ],
        "een.fleetCodeRecognitionEvent.v1": [
            "een.objectDetection.v1",
            "een.dotNumberRecognition.v1",
            "een.truckNumberRecognition.v1",
            "een.trailerNumberRecognition.v1",
            "een.croppedFrameImageUrl.v1",
            "een.fullFrameImageUrl.v1",
            "een.recognizedText.v1",
            "een.resourceDetails.v1",
        ],

        // Audio detection
        "een.gunShotAudioDetectionEvent.v1": [
            "een.audioDetection.v1",
            "een.geoLocation.v1",
        ],
        "een.t3AlarmAudioDetectionEvent.v1": [
            "een.audioDetection.v1",
        ],
        "een.t4AlarmAudioDetectionEvent.v1": [
            "een.audioDetection.v1",
        ],

        // POS events
        "een.posTransactionEvent.v1": [
            "een.posTransactionStart.v1",
            "een.posTransactionEnd.v1",
            "een.posTransactionItem.v1",
            "een.posTransactionPayment.v1",
            "een.posTransactionCartChangeTrail.v1",
            "een.posTransactionCardLoadSummary.v1",
            "een.posTransactionFlag.v1",
            "een.posTransactionLabel.v1",
            "een.rawData.v1",
            "een.displayLocationSummary.v1",
            "een.fullFrameImageUrl.v1",
        ],

        // Device and system events
        "een.deviceCloudStatusUpdateEvent.v1": [
            "een.deviceCloudStatusUpdate.v1",
            "een.deviceCloudPreviousStatus.v1",
        ],
        "een.deviceCloudConnectionStatusUpdateEvent.v1": [
            "een.deviceCloudConnectionStatusUpdate.v1",
            "een.deviceCloudConnectionPreviousStatus.v1",
        ],
        "een.edgeReportedDeviceStatusEvent.v1": [
            "een.deviceCommonStatusUpdate.v1",
            "een.deviceErrorStatusUpdate.v1",
        ],
        "een.deviceIOEvent.v1": [
            "een.deviceIO.v1",
        ],
        "een.deviceOperationEvent.v1": [
            "een.resourceDetails.v1",
            "een.deviceOperationDetails.v1",
            "een.deviceOperationSubStep.v1",
            "een.deviceOperationUpdate.v1",
        ],
        "een.ptzPositionUpdateEvent.v1": [
            "een.ptzPositionUpdate.v1",
        ],

        // Sensor events
        "een.doorStatusEvent.v1": [
            "een.measurementStringValueUpdate.v1",
        ],
        "een.batteryLevelUpdateEvent.v1": [
            "een.batteryLevelUpdate.v1",
        ],
        "een.measurementThresholdStatusEvent.v1": [
            "een.measurementThresholdStatus.v1",
            "een.measurementValueUpdate.v1",
            "een.measurementStringValueUpdate.v1",
        ],
        "een.thermalCameraThresholdStatusEvent.v1": [
            "een.thermalCameraValueUpdate.v1",
            "een.thermalMonitoredArea.v1",
        ],

        // Resource management events
        "een.layoutCreationEvent.v1": ["een.resourceDetails.v1"],
        "een.layoutUpdateEvent.v1": ["een.resourceDetails.v1"],
        "een.layoutDeletionEvent.v1": ["een.resourceDetails.v1"],
        "een.deviceCreationEvent.v1": ["een.resourceDetails.v1"],
        "een.deviceUpdateEvent.v1": ["een.resourceDetails.v1"],
        "een.deviceDeletionEvent.v1": ["een.resourceDetails.v1"],
        "een.userCreationEvent.v1": ["een.resourceDetails.v1"],
        "een.userUpdateEvent.v1": ["een.resourceDetails.v1"],
        "een.userDeletionEvent.v1": ["een.resourceDetails.v1"],
        "een.accountCreationEvent.v1": ["een.resourceDetails.v1"],
        "een.accountUpdateEvent.v1": ["een.resourceDetails.v1"],
        "een.accountDeletionEvent.v1": ["een.resourceDetails.v1"],

        // Job events
        "een.jobCreationEvent.v1": ["een.jobDetails.v1", "een.ownerDetails.v1"],
        "een.jobUpdateEvent.v1": ["een.jobDetails.v1", "een.ownerDetails.v1"],
        "een.jobDeletionEvent.v1": ["een.ownerDetails.v1"],

        // Access control events
        "een.accessActivationEvent.v1": [
            "een.credentialAccessActivation.v1",
            "een.creatorDetails.v1",
            "een.userAccessActivation.v1",
        ],

        // Safety and protocol events
        "een.panicButtonEvent.v1": ["een.geoLocation.v1"],
    ]

    /// Build the `include` parameter values for the given event types.
    /// Returns deduplicated schema names with the `data.` prefix.
    static func includeParameters(for eventTypes: [String]) -> [String] {
        var schemaSet = Set<String>()
        for eventType in eventTypes {
            if let typeSchemas = schemas[eventType] {
                for schema in typeSchemas {
                    schemaSet.insert("data.\(schema)")
                }
            }
        }
        return Array(schemaSet).sorted()
    }
}
