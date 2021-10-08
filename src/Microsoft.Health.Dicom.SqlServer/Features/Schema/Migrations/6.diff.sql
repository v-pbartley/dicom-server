/****************************************************************************************
Guidelines to create migration scripts - https://github.com/microsoft/healthcare-shared-components/tree/master/src/Microsoft.Health.SqlServer/SqlSchemaScriptsGuidelines.md

This diff is broken up into several sections:
 - The first transaction contains changes to tables and stored procedures.
 - The second transaction contains updates to indexes.
 - After the second transaction, there's an update to a full-text index which cannot be in a transaction.
******************************************************************************************/
SET XACT_ABORT ON

BEGIN TRANSACTION

/*************************************************************
    Partition Table
    Create table containing data partitions for light-weight multitenancy.
**************************************************************/
IF NOT EXISTS 
(
    SELECT *
    FROM    sys.tables
    WHERE   Name = 'Partition'
)
BEGIN
    CREATE TABLE dbo.Partition (
        PartitionKey                INT             NOT NULL, --PK  System-generated sequence
        PartitionName               VARCHAR(64)     NOT NULL, --    Client-generated unique name. Length allows GUID or UID.
        -- audit columns
        CreatedDate                 DATETIME2(7)    NOT NULL
    ) WITH (DATA_COMPRESSION = PAGE)

    CREATE UNIQUE CLUSTERED INDEX IXC_Partition ON dbo.Partition
    (
        PartitionKey
    )

    CREATE UNIQUE NONCLUSTERED INDEX IX_Partition_PartitionName ON dbo.Partition
    (
        PartitionName
    ) WITH (DATA_COMPRESSION = PAGE)

    -- Add default partition values
    INSERT INTO dbo.Partition
        (PartitionKey, PartitionName, CreatedDate)
    VALUES
        (1, 'Microsoft.Default', SYSUTCDATETIME())
END

/*************************************************************
    Partition Sequence
    Create sequence for partition key, with default value 1 reserved.
**************************************************************/
IF NOT EXISTS
(
    SELECT * FROM sys.sequences
    WHERE Name = 'PartitionKeySequence'
)
BEGIN
    CREATE SEQUENCE dbo.PartitionKeySequence
    AS INT
    START WITH 2    -- skipping the default partition
    INCREMENT BY 1
    MINVALUE 1
    NO CYCLE
    CACHE 10000
END

/*************************************************************
    Study Table
    Add PartitionKey column and update indexes.
**************************************************************/
IF NOT EXISTS 
(
    SELECT *
    FROM    sys.columns
    WHERE   NAME = 'PartitionKey'
        AND Object_id = OBJECT_ID('dbo.Study')
)
BEGIN
    ALTER TABLE dbo.Study
        ADD PartitionKey INT NOT NULL DEFAULT 1
END

/*************************************************************
    Series Table
    Add PartitionKey column and update indexes.
**************************************************************/
IF NOT EXISTS 
(
    SELECT *
    FROM    sys.columns
    WHERE   NAME = 'PartitionKey'
        AND Object_id = OBJECT_ID('dbo.Series')
)
BEGIN
    ALTER TABLE dbo.Series
        ADD PartitionKey INT NOT NULL DEFAULT 1
END

/*************************************************************
    Instance Table
    Add PartitionKey and PartitionName columns and update indexes.
**************************************************************/
IF NOT EXISTS 
(
    SELECT *
    FROM    sys.columns
    WHERE   NAME = 'PartitionKey'
        AND Object_id = OBJECT_ID('dbo.Instance')
)
BEGIN
    ALTER TABLE dbo.Instance
        ADD PartitionKey    INT             NOT NULL DEFAULT 1,
            PartitionName   VARCHAR(64)     NOT NULL DEFAULT 'Microsoft.Default'

    
END

/*************************************************************
    ChangeFeed Table
    Add PartitionName column and update indexes.
**************************************************************/
IF NOT EXISTS 
(
    SELECT *
    FROM    sys.columns
    WHERE   NAME = 'PartitionName'
        AND Object_id = OBJECT_ID('dbo.ChangeFeed')
)
BEGIN
    ALTER TABLE dbo.ChangeFeed
        ADD PartitionName VARCHAR(64) NOT NULL DEFAULT 'Microsoft.Default'
END

/*************************************************************
    DeletedInstance Table
    Add PartitionName column and update indexes.
**************************************************************/
IF NOT EXISTS 
(
    SELECT *
    FROM    sys.columns
    WHERE   NAME = 'PartitionName'
        AND Object_id = OBJECT_ID('dbo.DeletedInstance')
)
BEGIN
    ALTER TABLE dbo.DeletedInstance
        ADD PartitionName VARCHAR(64) NOT NULL DEFAULT 'Microsoft.Default'
END

/*************************************************************
    ExtendedQueryTagDateTime Table
    Add PartitionKey column and update indexes.
**************************************************************/
IF NOT EXISTS 
(
    SELECT *
    FROM    sys.columns
    WHERE   NAME = 'PartitionKey'
        AND Object_id = OBJECT_ID('dbo.ExtendedQueryTagDateTime ')
)
BEGIN
    ALTER TABLE dbo.ExtendedQueryTagDateTime 
        ADD PartitionKey INT NOT NULL DEFAULT 1
END

/*************************************************************
    ExtendedQueryTagDouble Table
    Add PartitionKey column and update indexes.
**************************************************************/
IF NOT EXISTS 
(
    SELECT *
    FROM    sys.columns
    WHERE   NAME = 'PartitionKey'
        AND Object_id = OBJECT_ID('dbo.ExtendedQueryTagDouble')
)
BEGIN
    ALTER TABLE dbo.ExtendedQueryTagDouble 
        ADD PartitionKey INT NOT NULL DEFAULT 1
END

/*************************************************************
    ExtendedQueryTagLong Table
    Add PartitionKey column and update indexes.
**************************************************************/
IF NOT EXISTS 
(
    SELECT *
    FROM    sys.columns
    WHERE   NAME = 'PartitionKey'
        AND Object_id = OBJECT_ID('dbo.ExtendedQueryTagLong')
)
BEGIN
    ALTER TABLE dbo.ExtendedQueryTagLong 
        ADD PartitionKey INT NOT NULL DEFAULT 1
END

/*************************************************************
    ExtendedQueryTagPersonName Table
    Add PartitionKey column and update indexes.
**************************************************************/
IF NOT EXISTS 
(
    SELECT *
    FROM    sys.columns
    WHERE   NAME = 'PartitionKey'
        AND Object_id = OBJECT_ID('dbo.ExtendedQueryTagPersonName')
)
BEGIN
    ALTER TABLE dbo.ExtendedQueryTagPersonName 
        ADD PartitionKey INT NOT NULL DEFAULT 1
END

/*************************************************************
    ExtendedQueryTagString Table
    Add PartitionKey column and update indexes.
**************************************************************/
IF NOT EXISTS 
(
    SELECT *
    FROM    sys.columns
    WHERE   NAME = 'PartitionKey'
        AND Object_id = OBJECT_ID('dbo.ExtendedQueryTagString')
)
BEGIN
    ALTER TABLE dbo.ExtendedQueryTagString 
        ADD PartitionKey INT NOT NULL DEFAULT 1
END
GO


/*************************************************************
    Stored Procedures
**************************************************************/

/*************************************************************
    Stored procedure for adding an instance.
**************************************************************/
--
-- STORED PROCEDURE
--     AddInstanceV3
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Adds a DICOM instance, now with partition.
--
-- PARAMETERS
--     @partitionName
--         * The client-provided data partition name.
--     @studyInstanceUid
--         * The study instance UID.
--     @seriesInstanceUid
--         * The series instance UID.
--     @sopInstanceUid
--         * The SOP instance UID.
--     @patientId
--         * The Id of the patient.
--     @patientName
--         * The name of the patient.
--     @referringPhysicianName
--         * The referring physician name.
--     @studyDate
--         * The study date.
--     @studyDescription
--         * The study description.
--     @accessionNumber
--         * The accession number associated for the study.
--     @modality
--         * The modality associated for the series.
--     @performedProcedureStepStartDate
--         * The date when the procedure for the series was performed.
--     @stringExtendedQueryTags
--         * String extended query tag data
--     @longExtendedQueryTags
--         * Long extended query tag data
--     @doubleExtendedQueryTags
--         * Double extended query tag data
--     @dateTimeExtendedQueryTags
--         * DateTime extended query tag data
--     @personNameExtendedQueryTags
--         * PersonName extended query tag data
-- RETURN VALUE
--     The watermark (version).
------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.AddInstanceV3
    @partitionName                      VARCHAR(64),
    @studyInstanceUid                   VARCHAR(64),
    @seriesInstanceUid                  VARCHAR(64),
    @sopInstanceUid                     VARCHAR(64),
    @patientId                          NVARCHAR(64),
    @patientName                        NVARCHAR(325) = NULL,
    @referringPhysicianName             NVARCHAR(325) = NULL,
    @studyDate                          DATE = NULL,
    @studyDescription                   NVARCHAR(64) = NULL,
    @accessionNumber                    NVARCHAR(64) = NULL,
    @modality                           NVARCHAR(16) = NULL,
    @performedProcedureStepStartDate    DATE = NULL,
    @patientBirthDate                   DATE = NULL,
    @manufacturerModelName              NVARCHAR(64) = NULL,
    @stringExtendedQueryTags dbo.InsertStringExtendedQueryTagTableType_1 READONLY,
    @longExtendedQueryTags dbo.InsertLongExtendedQueryTagTableType_1 READONLY,
    @doubleExtendedQueryTags dbo.InsertDoubleExtendedQueryTagTableType_1 READONLY,
    @dateTimeExtendedQueryTags dbo.InsertDateTimeExtendedQueryTagTableType_2 READONLY,
    @personNameExtendedQueryTags dbo.InsertPersonNameExtendedQueryTagTableType_1 READONLY,
    @initialStatus                      TINYINT
AS
BEGIN
    SET NOCOUNT ON

    SET XACT_ABORT ON
    BEGIN TRANSACTION

    DECLARE @currentDate DATETIME2(7) = SYSUTCDATETIME()
    DECLARE @existingStatus TINYINT
    DECLARE @newWatermark BIGINT
    DECLARE @partitionKey INT
    DECLARE @studyKey BIGINT
    DECLARE @seriesKey BIGINT
    DECLARE @instanceKey BIGINT

    SELECT @existingStatus = Status
    FROM dbo.Instance
    WHERE PartitionName = @partitionName
        AND StudyInstanceUid = @studyInstanceUid
        AND SeriesInstanceUid = @seriesInstanceUid
        AND SopInstanceUid = @sopInstanceUid

    IF @@ROWCOUNT <> 0
        -- The instance already exists. Set the state = @existingStatus to indicate what state it is in.
        THROW 50409, 'Instance already exists', @existingStatus;

    -- The instance does not exist, insert it.
    SET @newWatermark = NEXT VALUE FOR dbo.WatermarkSequence
    SET @instanceKey = NEXT VALUE FOR dbo.InstanceKeySequence

    -- Insert Partition
    SELECT @partitionKey = PartitionKey
    FROM dbo.Partition
    WHERE PartitionName = @partitionName

    IF @@ROWCOUNT = 0
    BEGIN
        SET @partitionKey = NEXT VALUE FOR dbo.PartitionKeySequence

        INSERT INTO dbo.Partition
            (PartitionKey, PartitionName, CreatedDate)
        VALUES
            (@partitionKey, @partitionName, @currentDate)
    END

    -- Insert Study
    SELECT @studyKey = StudyKey
    FROM dbo.Study WITH(UPDLOCK)
    WHERE PartitionKey = @partitionKey
        AND StudyInstanceUid = @studyInstanceUid

    IF @@ROWCOUNT = 0
    BEGIN
        SET @studyKey = NEXT VALUE FOR dbo.StudyKeySequence

        INSERT INTO dbo.Study
            (PartitionKey, StudyKey, StudyInstanceUid, PatientId, PatientName, PatientBirthDate, ReferringPhysicianName, StudyDate, StudyDescription, AccessionNumber)
        VALUES
            (@partitionKey, @studyKey, @studyInstanceUid, @patientId, @patientName, @patientBirthDate, @referringPhysicianName, @studyDate, @studyDescription, @accessionNumber)
    END
    ELSE
    BEGIN
        -- Latest wins
        UPDATE dbo.Study
        SET PatientId = @patientId, PatientName = @patientName, PatientBirthDate = @patientBirthDate, ReferringPhysicianName = @referringPhysicianName, StudyDate = @studyDate, StudyDescription = @studyDescription, AccessionNumber = @accessionNumber
        WHERE StudyKey = @studyKey
    END

    -- Insert Series
    SELECT @seriesKey = SeriesKey
    FROM dbo.Series WITH(UPDLOCK)
    WHERE StudyKey = @studyKey
    AND SeriesInstanceUid = @seriesInstanceUid

    IF @@ROWCOUNT = 0
    BEGIN
        SET @seriesKey = NEXT VALUE FOR dbo.SeriesKeySequence

        INSERT INTO dbo.Series
            (PartitionKey, StudyKey, SeriesKey, SeriesInstanceUid, Modality, PerformedProcedureStepStartDate, ManufacturerModelName)
        VALUES
            (@partitionKey, @studyKey, @seriesKey, @seriesInstanceUid, @modality, @performedProcedureStepStartDate, @manufacturerModelName)
    END
    ELSE
    BEGIN
        -- Latest wins
        UPDATE dbo.Series
        SET Modality = @modality, PerformedProcedureStepStartDate = @performedProcedureStepStartDate, ManufacturerModelName = @manufacturerModelName
        WHERE SeriesKey = @seriesKey
        AND StudyKey = @studyKey
        AND PartitionKey = @partitionKey
    END

    -- Insert Instance
    INSERT INTO dbo.Instance
        (PartitionKey, StudyKey, SeriesKey, InstanceKey, PartitionName, StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, Watermark, Status, LastStatusUpdatedDate, CreatedDate)
    VALUES
        (@partitionKey, @studyKey, @seriesKey, @instanceKey, @partitionName, @studyInstanceUid, @seriesInstanceUid, @sopInstanceUid, @newWatermark, @initialStatus, @currentDate, @currentDate)

    -- Insert Extended Query Tags

    -- String Key tags
    IF EXISTS (SELECT 1 FROM @stringExtendedQueryTags)
    BEGIN
        MERGE INTO dbo.ExtendedQueryTagString AS T
        USING
        (
            SELECT input.TagKey, input.TagValue, input.TagLevel
            FROM @stringExtendedQueryTags input
            INNER JOIN dbo.ExtendedQueryTag WITH (REPEATABLEREAD)
            ON dbo.ExtendedQueryTag.TagKey = input.TagKey
            -- Not merge on extended query tag which is being deleted.
            AND dbo.ExtendedQueryTag.TagStatus <> 2
        ) AS S
        ON T.TagKey = S.TagKey
            AND T.PartitionKey = @partitionKey
            AND T.StudyKey = @studyKey
            -- Null SeriesKey indicates a Study level tag, no need to compare SeriesKey
            AND ISNULL(T.SeriesKey, @seriesKey) = @seriesKey
            -- Null InstanceKey indicates a Study/Series level tag, no to compare InstanceKey
            AND ISNULL(T.InstanceKey, @instanceKey) = @instanceKey
        WHEN MATCHED THEN
            UPDATE SET T.Watermark = @newWatermark, T.TagValue = S.TagValue
        WHEN NOT MATCHED THEN
            INSERT (TagKey, TagValue, PartitionKey, StudyKey, SeriesKey, InstanceKey, Watermark)
            VALUES(
            S.TagKey,
            S.TagValue,
            @partitionKey,
            @studyKey,
            -- When TagLevel is not Study, we should fill SeriesKey
            (CASE WHEN S.TagLevel <> 2 THEN @seriesKey ELSE NULL END),
            -- When TagLevel is Instance, we should fill InstanceKey
            (CASE WHEN S.TagLevel = 0 THEN @instanceKey ELSE NULL END),
            @newWatermark);
    END

    -- Long Key tags
    IF EXISTS (SELECT 1 FROM @longExtendedQueryTags)
    BEGIN
        MERGE INTO dbo.ExtendedQueryTagLong AS T
        USING
        (
            SELECT input.TagKey, input.TagValue, input.TagLevel
            FROM @longExtendedQueryTags input
            INNER JOIN dbo.ExtendedQueryTag WITH (REPEATABLEREAD)
            ON dbo.ExtendedQueryTag.TagKey = input.TagKey
            AND dbo.ExtendedQueryTag.TagStatus <> 2
        ) AS S
        ON T.TagKey = S.TagKey
            AND T.PartitionKey = @partitionKey
            AND T.StudyKey = @studyKey
            AND ISNULL(T.SeriesKey, @seriesKey) = @seriesKey
            AND ISNULL(T.InstanceKey, @instanceKey) = @instanceKey
        WHEN MATCHED THEN
            UPDATE SET T.Watermark = @newWatermark, T.TagValue = S.TagValue
        WHEN NOT MATCHED THEN
            INSERT (TagKey, TagValue, PartitionKey, StudyKey, SeriesKey, InstanceKey, Watermark)
            VALUES(
            S.TagKey,
            S.TagValue,
            @partitionKey,
            @studyKey,
            (CASE WHEN S.TagLevel <> 2 THEN @seriesKey ELSE NULL END),
            (CASE WHEN S.TagLevel = 0 THEN @instanceKey ELSE NULL END),
            @newWatermark);
    END

    -- Double Key tags
    IF EXISTS (SELECT 1 FROM @doubleExtendedQueryTags)
    BEGIN
        MERGE INTO dbo.ExtendedQueryTagDouble AS T
        USING
        (
            SELECT input.TagKey, input.TagValue, input.TagLevel
            FROM @doubleExtendedQueryTags input
            INNER JOIN dbo.ExtendedQueryTag WITH (REPEATABLEREAD)
            ON dbo.ExtendedQueryTag.TagKey = input.TagKey
            AND dbo.ExtendedQueryTag.TagStatus <> 2
        ) AS S
        ON T.TagKey = S.TagKey
            AND T.PartitionKey = @partitionKey
            AND T.StudyKey = @studyKey
            AND ISNULL(T.SeriesKey, @seriesKey) = @seriesKey
            AND ISNULL(T.InstanceKey, @instanceKey) = @instanceKey
        WHEN MATCHED THEN
            UPDATE SET T.Watermark = @newWatermark, T.TagValue = S.TagValue
        WHEN NOT MATCHED THEN
            INSERT (TagKey, TagValue, PartitionKey, StudyKey, SeriesKey, InstanceKey, Watermark)
            VALUES(
            S.TagKey,
            S.TagValue,
            @partitionKey,
            @studyKey,
            (CASE WHEN S.TagLevel <> 2 THEN @seriesKey ELSE NULL END),
            (CASE WHEN S.TagLevel = 0 THEN @instanceKey ELSE NULL END),
            @newWatermark);
    END

    -- DateTime Key tags
    IF EXISTS (SELECT 1 FROM @dateTimeExtendedQueryTags)
    BEGIN
        MERGE INTO dbo.ExtendedQueryTagDateTime AS T
        USING
        (
            SELECT input.TagKey, input.TagValue, input.TagValueUtc, input.TagLevel
            FROM @dateTimeExtendedQueryTags input
            INNER JOIN dbo.ExtendedQueryTag WITH (REPEATABLEREAD)
            ON dbo.ExtendedQueryTag.TagKey = input.TagKey
            AND dbo.ExtendedQueryTag.TagStatus <> 2
        ) AS S
        ON T.TagKey = S.TagKey
            AND T.PartitionKey = @partitionKey
            AND T.StudyKey = @studyKey
            AND ISNULL(T.SeriesKey, @seriesKey) = @seriesKey
            AND ISNULL(T.InstanceKey, @instanceKey) = @instanceKey
        WHEN MATCHED THEN
            UPDATE SET T.Watermark = @newWatermark, T.TagValue = S.TagValue
        WHEN NOT MATCHED THEN
            INSERT (TagKey, TagValue, PartitionKey, StudyKey, SeriesKey, InstanceKey, Watermark, TagValueUtc)
            VALUES(
            S.TagKey,
            S.TagValue,
            @partitionKey,
            @studyKey,
            (CASE WHEN S.TagLevel <> 2 THEN @seriesKey ELSE NULL END),
            (CASE WHEN S.TagLevel = 0 THEN @instanceKey ELSE NULL END),
            @newWatermark,
            S.TagValueUtc);
    END

    -- PersonName Key tags
    IF EXISTS (SELECT 1 FROM @personNameExtendedQueryTags)
    BEGIN
        MERGE INTO dbo.ExtendedQueryTagPersonName AS T
        USING
        (
            SELECT input.TagKey, input.TagValue, input.TagLevel
            FROM @personNameExtendedQueryTags input
            INNER JOIN dbo.ExtendedQueryTag WITH (REPEATABLEREAD)
            ON dbo.ExtendedQueryTag.TagKey = input.TagKey
            AND dbo.ExtendedQueryTag.TagStatus <> 2
        ) AS S
        ON T.TagKey = S.TagKey
            AND T.PartitionKey = @partitionKey
            AND T.StudyKey = @studyKey
            AND ISNULL(T.SeriesKey, @seriesKey) = @seriesKey
            AND ISNULL(T.InstanceKey, @instanceKey) = @instanceKey
        WHEN MATCHED THEN
            UPDATE SET T.Watermark = @newWatermark, T.TagValue = S.TagValue
        WHEN NOT MATCHED THEN
            INSERT (TagKey, TagValue, PartitionKey, StudyKey, SeriesKey, InstanceKey, Watermark)
            VALUES(
            S.TagKey,
            S.TagValue,
            @partitionKey,
            @studyKey,
            (CASE WHEN S.TagLevel <> 2 THEN @seriesKey ELSE NULL END),
            (CASE WHEN S.TagLevel = 0 THEN @instanceKey ELSE NULL END),
            @newWatermark);
    END

    SELECT @newWatermark

    COMMIT TRANSACTION
END
GO

/***************************************************************************************/
-- STORED PROCEDURE
--     BeginAddInstanceV2
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Begins the addition of a DICOM instance, now with partition.
--
-- PARAMETERS
--     @partitionName
--         * The client-provided data partition name.
--     @studyInstanceUid
--         * The study instance UID.
--     @seriesInstanceUid
--         * The series instance UID.
--     @sopInstanceUid
--         * The SOP instance UID.
--     @patientId
--         * The Id of the patient.
--     @patientName
--         * The name of the patient.
--     @referringPhysicianName
--         * The referring physician name.
--     @studyDate
--         * The study date.
--     @studyDescription
--         * The study description.
--     @accessionNumber
--         * The accession number associated for the study.
--     @modality
--         * The modality associated for the series.
--     @performedProcedureStepStartDate
--         * The date when the procedure for the series was performed.
--     @stringExtendedQueryTags
--         * String extended query tag data
--     @longExtendedQueryTags
--         * Long extended query tag data
--     @doubleExtendedQueryTags
--         * Double extended query tag data
--     @dateTimeExtendedQueryTags
--         * DateTime extended query tag data
--     @personNameExtendedQueryTags
--         * PersonName extended query tag data
-- RETURN VALUE
--     The watermark (version).
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.BeginAddInstanceV2
    @partitionName                      VARCHAR(64),
    @studyInstanceUid                   VARCHAR(64),
    @seriesInstanceUid                  VARCHAR(64),
    @sopInstanceUid                     VARCHAR(64),
    @patientId                          NVARCHAR(64),
    @patientName                        NVARCHAR(325) = NULL,
    @referringPhysicianName             NVARCHAR(325) = NULL,
    @studyDate                          DATE = NULL,
    @studyDescription                   NVARCHAR(64) = NULL,
    @accessionNumber                    NVARCHAR(64) = NULL,
    @modality                           NVARCHAR(16) = NULL,
    @performedProcedureStepStartDate    DATE = NULL,
    @patientBirthDate                   DATE = NULL,
    @manufacturerModelName              NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    BEGIN TRANSACTION

    DECLARE @currentDate DATETIME2(7) = SYSUTCDATETIME()
    DECLARE @existingStatus TINYINT
    DECLARE @newWatermark BIGINT
    DECLARE @partitionKey INT
    DECLARE @studyKey BIGINT
    DECLARE @seriesKey BIGINT
    DECLARE @instanceKey BIGINT

    SELECT @existingStatus = Status
    FROM dbo.Instance WITH(HOLDLOCK)
    WHERE PartitionName = @partitionName
        AND StudyInstanceUid = @studyInstanceUid
        AND SeriesInstanceUid = @seriesInstanceUid
        AND SopInstanceUid = @sopInstanceUid

    IF @@ROWCOUNT <> 0
        -- The instance already exists. Set the state = @existingStatus to indicate what state it is in.
        THROW 50409, 'Instance already exists', @existingStatus;

    -- Insert Partition
    SELECT @partitionKey = PartitionKey
    FROM dbo.Partition
    WHERE PartitionName = @partitionName

    IF @@ROWCOUNT = 0
    BEGIN
        SET @partitionKey = NEXT VALUE FOR dbo.PartitionKeySequence

        INSERT INTO dbo.Partition
            (PartitionKey, PartitionName, CreatedDate)
        VALUES
            (@partitionKey, @partitionName, @currentDate)
    END

    -- Insert Study
    SELECT @studyKey = StudyKey
    FROM dbo.Study WITH(HOLDLOCK)
    WHERE PartitionKey = @partitionKey
        AND StudyInstanceUid = @studyInstanceUid

    IF @@ROWCOUNT = 0
    BEGIN
        SET @studyKey = NEXT VALUE FOR dbo.StudyKeySequence

        INSERT INTO dbo.Study
            (PartitionKey, StudyKey, StudyInstanceUid, PatientId, PatientName, PatientBirthDate, ReferringPhysicianName, StudyDate, StudyDescription, AccessionNumber)
        VALUES
            (@partitionKey, @studyKey, @studyInstanceUid, @patientId, @patientName, @patientBirthDate, @referringPhysicianName, @studyDate, @studyDescription, @accessionNumber)
    END
    ELSE
    BEGIN
        -- Latest wins
        UPDATE dbo.Study
        SET PatientId = @patientId, PatientName = @patientName, PatientBirthDate = @patientBirthDate, ReferringPhysicianName = @referringPhysicianName, StudyDate = @studyDate, StudyDescription = @studyDescription, AccessionNumber = @accessionNumber
        WHERE StudyKey = @studyKey
    END

    -- Insert Series
    SELECT @seriesKey = SeriesKey
    FROM dbo.Series WITH(HOLDLOCK)
    WHERE StudyKey = @studyKey
    AND SeriesInstanceUid = @seriesInstanceUid

    IF @@ROWCOUNT = 0
    BEGIN
        SET @seriesKey = NEXT VALUE FOR dbo.SeriesKeySequence

        INSERT INTO dbo.Series
            (PartitionKey, StudyKey, SeriesKey, SeriesInstanceUid, Modality, PerformedProcedureStepStartDate, ManufacturerModelName)
        VALUES
            (@partitionKey, @studyKey, @seriesKey, @seriesInstanceUid, @modality, @performedProcedureStepStartDate, @manufacturerModelName)
    END
    ELSE
    BEGIN
        -- Latest wins
        UPDATE dbo.Series
        SET Modality = @modality, PerformedProcedureStepStartDate = @performedProcedureStepStartDate, ManufacturerModelName = @manufacturerModelName
        WHERE SeriesKey = @seriesKey
        AND StudyKey = @studyKey
        AND PartitionKey = @partitionKey
    END

    -- Insert Instance
    INSERT INTO dbo.Instance
        (PartitionKey, StudyKey, SeriesKey, InstanceKey, PartitionName, StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, Watermark, Status, LastStatusUpdatedDate, CreatedDate)
    VALUES
        (@partitionKey, @studyKey, @seriesKey, @instanceKey, @partitionName, @studyInstanceUid, @seriesInstanceUid, @sopInstanceUid, @newWatermark, 0, @currentDate, @currentDate)

    SELECT @newWatermark

    COMMIT TRANSACTION
END
GO

/***************************************************************************************/
-- STORED PROCEDURE
--     EndAddInstanceV2
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Completes the addition of a DICOM instance.
--
-- PARAMETERS
--     @partitionName
--         * The client-provided data partition name.
--     @studyInstanceUid
--         * The study instance UID.
--     @seriesInstanceUid
--         * The series instance UID.
--     @sopInstanceUid
--         * The SOP instance UID.
--     @watermark
--         * The watermark.
--     @maxTagKey
--         * Max ExtendedQueryTag key
--     @stringExtendedQueryTags
--         * String extended query tag data
--     @longExtendedQueryTags
--         * Long extended query tag data
--     @doubleExtendedQueryTags
--         * Double extended query tag data
--     @dateTimeExtendedQueryTags
--         * DateTime extended query tag data
--     @personNameExtendedQueryTags
--         * PersonName extended query tag data
-- RETURN VALUE
--     None
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.EndAddInstanceV2
    @partitionName     VARCHAR(64),
    @studyInstanceUid  VARCHAR(64),
    @seriesInstanceUid VARCHAR(64),
    @sopInstanceUid    VARCHAR(64),
    @watermark         BIGINT,
    @maxTagKey         INT = NULL,
    @stringExtendedQueryTags dbo.InsertStringExtendedQueryTagTableType_1         READONLY,
    @longExtendedQueryTags dbo.InsertLongExtendedQueryTagTableType_1             READONLY,
    @doubleExtendedQueryTags dbo.InsertDoubleExtendedQueryTagTableType_1         READONLY,
    @dateTimeExtendedQueryTags dbo.InsertDateTimeExtendedQueryTagTableType_1     READONLY,
    @personNameExtendedQueryTags dbo.InsertPersonNameExtendedQueryTagTableType_1 READONLY
AS
BEGIN
    SET NOCOUNT ON

    SET XACT_ABORT ON
    BEGIN TRANSACTION

        -- This check ensures the client is not potentially missing 1 or more query tags that may need to be indexed.
        -- Note that if @maxTagKey is NULL, < will always return UNKNOWN.
        IF @maxTagKey < (SELECT ISNULL(MAX(TagKey), 0) FROM dbo.ExtendedQueryTag WITH (HOLDLOCK))
            THROW 50409, 'Max extended query tag key does not match', 10

        DECLARE @currentDate DATETIME2(7) = SYSUTCDATETIME()

        UPDATE dbo.Instance
        SET Status = 1, LastStatusUpdatedDate = @currentDate
        WHERE PartitionName = @partitionName
            AND StudyInstanceUid = @studyInstanceUid
            AND SeriesInstanceUid = @seriesInstanceUid
            AND SopInstanceUid = @sopInstanceUid
            AND Watermark = @watermark

        IF @@ROWCOUNT = 0
            THROW 50404, 'Instance does not exist', 1 -- The instance does not exist. Perhaps it was deleted?

        EXEC dbo.IndexInstance
            @watermark,
            @stringExtendedQueryTags,
            @longExtendedQueryTags,
            @doubleExtendedQueryTags,
            @dateTimeExtendedQueryTags,
            @personNameExtendedQueryTags

        -- Insert to change feed.
        -- Currently this procedure is used only updating the status to created
        -- If that changes an if condition is needed.
        INSERT INTO dbo.ChangeFeed
            (Timestamp, Action, PartitionName, StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, OriginalWatermark)
        VALUES
            (@currentDate, 0, @partitionName, @studyInstanceUid, @seriesInstanceUid, @sopInstanceUid, @watermark)

        -- Update existing instance currentWatermark to latest
        UPDATE dbo.ChangeFeed
        SET CurrentWatermark      = @watermark
        WHERE PartitionName = @partitionName
            AND StudyInstanceUid = @studyInstanceUid
            AND SeriesInstanceUid = @seriesInstanceUid
            AND SopInstanceUid = @sopInstanceUid

    COMMIT TRANSACTION
END
GO

/***************************************************************************************/
-- STORED PROCEDURE
--     DeleteDeletedInstanceV2
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Removes a deleted instance from the DeletedInstance table
--
-- PARAMETERS
--     @partitionName
--         * The client-provided data partition name.
--     @studyInstanceUid
--         * The study instance UID.
--     @seriesInstanceUid
--         * The series instance UID.
--     @sopInstanceUid
--         * The SOP instance UID.
--     @watermark
--         * The watermark of the entry
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.DeleteDeletedInstanceV2(
    @partitionName      VARCHAR(64),
    @studyInstanceUid   VARCHAR(64),
    @seriesInstanceUid  VARCHAR(64),
    @sopInstanceUid     VARCHAR(64),
    @watermark          BIGINT
)
AS
BEGIN
    SET NOCOUNT ON

    DELETE
    FROM    dbo.DeletedInstance
    WHERE   PartitionName = @partitionName
        AND     StudyInstanceUid = @studyInstanceUid
        AND     SeriesInstanceUid = @seriesInstanceUid
        AND     SopInstanceUid = @sopInstanceUid
        AND     Watermark = @watermark
END
GO

/***************************************************************************************/
-- STORED PROCEDURE
--     DeleteInstanceV2
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Removes the specified instance(s) and places them in the DeletedInstance table for later removal
--
-- PARAMETERS
--     @partitionName
--         * The client-provided data partition name.
--     @cleanupAfter
--         * The date time offset that the instance can be cleaned up.
--     @createdStatus
--         * Status value representing the created state.
--     @studyInstanceUid
--         * The study instance UID.
--     @seriesInstanceUid
--         * The series instance UID.
--     @sopInstanceUid
--         * The SOP instance UID.
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.DeleteInstanceV2
    @cleanupAfter       DATETIMEOFFSET(0),
    @createdStatus      TINYINT,
    @partitionName      VARCHAR(64),
    @studyInstanceUid   VARCHAR(64),
    @seriesInstanceUid  VARCHAR(64) = null,
    @sopInstanceUid     VARCHAR(64) = null
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON

    BEGIN TRANSACTION

    DECLARE @deletedInstances AS TABLE
        (PartitionName VARCHAR(64),
            StudyInstanceUid VARCHAR(64),
            SeriesInstanceUid VARCHAR(64),
            SopInstanceUid VARCHAR(64),
            Status TINYINT,
            Watermark BIGINT)

    DECLARE @partitionKey INT
    DECLARE @studyKey BIGINT
    DECLARE @seriesKey BIGINT
    DECLARE @instanceKey BIGINT
    DECLARE @deletedDate DATETIME2 = SYSUTCDATETIME()

    -- Get the partition, study, series and instance PK
    SELECT  @partitionKey = PartitionKey,
    @studyKey = StudyKey,
    @seriesKey = CASE @seriesInstanceUid WHEN NULL THEN NULL ELSE SeriesKey END,
    @instanceKey = CASE @sopInstanceUid WHEN NULL THEN NULL ELSE InstanceKey END
    FROM    dbo.Instance
    WHERE   PartitionName = @partitionName
        AND     StudyInstanceUid = @studyInstanceUid
        AND     SeriesInstanceUid = ISNULL(@seriesInstanceUid, SeriesInstanceUid)
        AND     SopInstanceUid = ISNULL(@sopInstanceUid, SopInstanceUid)

    -- Delete the instance and insert the details into DeletedInstance and ChangeFeed
    DELETE  dbo.Instance
        OUTPUT deleted.PartitionName, deleted.StudyInstanceUid, deleted.SeriesInstanceUid, deleted.SopInstanceUid, deleted.Status, deleted.Watermark
        INTO @deletedInstances
    WHERE   PartitionName = @partitionName
        AND     StudyInstanceUid = @studyInstanceUid
        AND     SeriesInstanceUid = ISNULL(@seriesInstanceUid, SeriesInstanceUid)
        AND     SopInstanceUid = ISNULL(@sopInstanceUid, SopInstanceUid)

    IF @@ROWCOUNT = 0
        THROW 50404, 'Instance not found', 1

    -- Deleting tag errors
    DECLARE @deletedTags AS TABLE
    (
        TagKey BIGINT
    )
    DELETE XQTE
        OUTPUT deleted.TagKey
        INTO @deletedTags
    FROM dbo.ExtendedQueryTagError as XQTE
    INNER JOIN @deletedInstances as d
    ON XQTE.Watermark = d.Watermark

    -- Update error count
    IF EXISTS (SELECT * FROM @deletedTags)
    BEGIN
        DECLARE @deletedTagCounts AS TABLE
        (
            TagKey BIGINT,
            ErrorCount INT
        )

        -- Calculate error count
        INSERT INTO @deletedTagCounts
            (TagKey, ErrorCount)
        SELECT TagKey, COUNT(1)
        FROM @deletedTags
        GROUP BY TagKey

        UPDATE XQT
        SET XQT.ErrorCount = XQT.ErrorCount - DTC.ErrorCount
        FROM dbo.ExtendedQueryTag AS XQT
        INNER JOIN @deletedTagCounts AS DTC
        ON XQT.TagKey = DTC.TagKey
    END

    -- Deleting indexed instance tags
    DELETE
    FROM    dbo.ExtendedQueryTagString
    WHERE   StudyKey = @studyKey
    AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)
    AND     InstanceKey = ISNULL(@instanceKey, InstanceKey)

    DELETE
    FROM    dbo.ExtendedQueryTagLong
    WHERE   StudyKey = @studyKey
    AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)
    AND     InstanceKey = ISNULL(@instanceKey, InstanceKey)

    DELETE
    FROM    dbo.ExtendedQueryTagDouble
    WHERE   StudyKey = @studyKey
    AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)
    AND     InstanceKey = ISNULL(@instanceKey, InstanceKey)

    DELETE
    FROM    dbo.ExtendedQueryTagDateTime
    WHERE   StudyKey = @studyKey
    AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)
    AND     InstanceKey = ISNULL(@instanceKey, InstanceKey)

    DELETE
    FROM    dbo.ExtendedQueryTagPersonName
    WHERE   StudyKey = @studyKey
    AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)
    AND     InstanceKey = ISNULL(@instanceKey, InstanceKey)

    INSERT INTO dbo.DeletedInstance
    (PartitionName, StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, Watermark, DeletedDateTime, RetryCount, CleanupAfter)
    SELECT PartitionName, StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, Watermark, @deletedDate, 0 , @cleanupAfter
    FROM @deletedInstances

    INSERT INTO dbo.ChangeFeed
    (TimeStamp, Action, PartitionName, StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, OriginalWatermark)
    SELECT @deletedDate, 1, PartitionName, StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, Watermark
    FROM @deletedInstances
    WHERE Status = @createdStatus

    UPDATE cf
    SET cf.CurrentWatermark = NULL
    FROM dbo.ChangeFeed cf WITH(FORCESEEK)
    JOIN @deletedInstances d
    ON cf.PartitionName = d.PartitionName
        AND cf.StudyInstanceUid = d.StudyInstanceUid
        AND cf.SeriesInstanceUid = d.SeriesInstanceUid
        AND cf.SopInstanceUid = d.SopInstanceUid

    -- If this is the last instance for a series, remove the series
    IF NOT EXISTS ( SELECT  *
                    FROM    dbo.Instance WITH(HOLDLOCK, UPDLOCK)
                    WHERE   StudyKey = @studyKey
                    AND     SeriesInstanceUid = ISNULL(@seriesInstanceUid, SeriesInstanceUid))
    BEGIN
        DELETE
        FROM    dbo.Series
        WHERE   StudyKey = @studyKey
        AND     SeriesInstanceUid = ISNULL(@seriesInstanceUid, SeriesInstanceUid)

        -- Deleting indexed series tags
        DELETE
        FROM    dbo.ExtendedQueryTagString
        WHERE   StudyKey = @studyKey
        AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)

        DELETE
        FROM    dbo.ExtendedQueryTagLong
        WHERE   StudyKey = @studyKey
        AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)

        DELETE
        FROM    dbo.ExtendedQueryTagDouble
        WHERE   StudyKey = @studyKey
        AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)

        DELETE
        FROM    dbo.ExtendedQueryTagDateTime
        WHERE   StudyKey = @studyKey
        AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)

        DELETE
        FROM    dbo.ExtendedQueryTagPersonName
        WHERE   StudyKey = @studyKey
        AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)
    END

    -- If we've removing the series, see if it's the last for a study and if so, remove the study
    IF NOT EXISTS ( SELECT  *
                    FROM    dbo.Series WITH(HOLDLOCK, UPDLOCK)
                    WHERE   Studykey = @studyKey)
    BEGIN
        DELETE
        FROM    dbo.Study
        WHERE   StudyKey = @studyKey

        -- Deleting indexed study tags
        DELETE
        FROM    dbo.ExtendedQueryTagString
        WHERE   StudyKey = @studyKey

        DELETE
        FROM    dbo.ExtendedQueryTagLong
        WHERE   StudyKey = @studyKey

        DELETE
        FROM    dbo.ExtendedQueryTagDouble
        WHERE   StudyKey = @studyKey

        DELETE
        FROM    dbo.ExtendedQueryTagDateTime
        WHERE   StudyKey = @studyKey

        DELETE
        FROM    dbo.ExtendedQueryTagPersonName
        WHERE   StudyKey = @studyKey
    END

    COMMIT TRANSACTION
END
GO

/***************************************************************************************/
-- STORED PROCEDURE
--     GetChangeFeedLatestV2
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Gets the latest dicom change
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.GetChangeFeedLatestV2
AS
BEGIN
    SET NOCOUNT     ON
    SET XACT_ABORT  ON

    SELECT  TOP(1)
            Sequence,
            Timestamp,
            Action,
            PartitionName,
            StudyInstanceUid,
            SeriesInstanceUid,
            SopInstanceUid,
            OriginalWatermark,
            CurrentWatermark
    FROM    dbo.ChangeFeed
    ORDER BY Sequence DESC
END
GO

/***************************************************************************************/
-- STORED PROCEDURE
--     GetChangeFeedV2
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Gets a stream of dicom changes (instance adds and deletes)
--
-- PARAMETERS
--     @limit
--         * Max rows to return
--     @offet
--         * Rows to skip
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.GetChangeFeedV2 (
    @limit      INT,
    @offset     BIGINT)
AS
BEGIN
    SET NOCOUNT     ON
    SET XACT_ABORT  ON

    SELECT  Sequence,
            Timestamp,
            Action,
            PartitionName,
            StudyInstanceUid,
            SeriesInstanceUid,
            SopInstanceUid,
            OriginalWatermark,
            CurrentWatermark
    FROM    dbo.ChangeFeed
    WHERE   Sequence BETWEEN @offset+1 AND @offset+@limit
    ORDER BY Sequence
END
GO

/***************************************************************************************/
-- STORED PROCEDURE
--     GetExtendedQueryTagErrorsV2
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Gets the extended query tag errors by tag path.
--
-- PARAMETERS
--     @tagPath
--         * The TagPath for the extended query tag for which we retrieve error(s).
--     @limit
--         * The maximum number of results to retrieve.
--     @offset
--         * The offset from which to retrieve paginated results.
--
-- RETURN VALUE
--     The tag error fields and the corresponding instance UIDs.
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.GetExtendedQueryTagErrorsV2
    @tagPath VARCHAR(64),
    @limit   INT,
    @offset  INT
AS
BEGIN
    SET NOCOUNT     ON
    SET XACT_ABORT  ON

    DECLARE @tagKey INT
    SELECT @tagKey = TagKey
    FROM dbo.ExtendedQueryTag WITH(HOLDLOCK)
    WHERE dbo.ExtendedQueryTag.TagPath = @tagPath

    -- Check existence
    IF (@@ROWCOUNT = 0)
        THROW 50404, 'extended query tag not found', 1

    SELECT
        TagKey,
        ErrorCode,
        CreatedTime,
        PartitionName,
        StudyInstanceUid,
        SeriesInstanceUid,
        SopInstanceUid
    FROM dbo.ExtendedQueryTagError AS XQTE
    INNER JOIN dbo.Instance AS I
    ON XQTE.Watermark = I.Watermark
    WHERE XQTE.TagKey = @tagKey
    ORDER BY CreatedTime ASC, XQTE.Watermark ASC, TagKey ASC
    OFFSET @offset ROWS
    FETCH NEXT @limit ROWS ONLY
END
GO

/***************************************************************************************/
-- STORED PROCEDURE
--     GetInstanceV2
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Gets valid dicom instances at study/series/instance level
--
-- PARAMETERS
--     @invalidStatus
--         * Filter criteria to search only valid instances
--     @partitionName
--         * The client-provided data partition name.
--     @studyInstanceUid
--         * The study instance UID.
--     @seriesInstanceUid
--         * The series instance UID.
--     @sopInstanceUid
--         * The SOP instance UID.
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.GetInstanceV2 (
    @validStatus        TINYINT,
    @partitionName      VARCHAR(64),
    @studyInstanceUid   VARCHAR(64),
    @seriesInstanceUid  VARCHAR(64) = NULL,
    @sopInstanceUid     VARCHAR(64) = NULL
)
AS
BEGIN
    SET NOCOUNT     ON
    SET XACT_ABORT  ON


    SELECT  StudyInstanceUid,
            SeriesInstanceUid,
            SopInstanceUid,
            Watermark
    FROM    dbo.Instance
    WHERE   PartitionName           = @partitionName
            AND StudyInstanceUid    = @studyInstanceUid
            AND SeriesInstanceUid   = ISNULL(@seriesInstanceUid, SeriesInstanceUid)
            AND SopInstanceUid      = ISNULL(@sopInstanceUid, SopInstanceUid)
            AND Status              = @validStatus

END
GO

/**************************************************************/
--
-- STORED PROCEDURE
--     GetInstancesByWatermarkRangeV2
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Get instances by given watermark range.
--
-- PARAMETERS
--     @startWatermark
--         * The inclusive start watermark.
--     @endWatermark
--         * The inclusive end watermark.
--     @status
--         * The instance status.
-- RETURN VALUE
--     The instance identifiers.
------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.GetInstancesByWatermarkRangeV2
    @startWatermark BIGINT,
    @endWatermark BIGINT,
    @status TINYINT
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    SELECT PartitionName,
           StudyInstanceUid,
           SeriesInstanceUid,
           SopInstanceUid,
           Watermark
    FROM dbo.Instance
    WHERE Watermark BETWEEN @startWatermark AND @endWatermark
          AND Status = @status
END
GO

/***************************************************************************************/
-- STORED PROCEDURE
--     GetPartitions
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Gets all data partitions (except the default partition)
--
-- PARAMETERS
--
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.GetPartitions AS
BEGIN
    SET NOCOUNT     ON
    SET XACT_ABORT  ON

    SELECT  PartitionKey,
            PartitionName,
            CreatedDate
    FROM    dbo.Partition
    WHERE PartitionKey > 1

END
GO

/***************************************************************************************/
-- STORED PROCEDURE
--     IncrementDeletedInstanceRetryV2
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Increments the retryCount of and retryAfter of a deleted instance
--
-- PARAMETERS
--     @partitionName
--         * The client-provided data partition name.
--     @studyInstanceUid
--         * The study instance UID.
--     @seriesInstanceUid
--         * The series instance UID.
--     @sopInstanceUid
--         * The SOP instance UID.
--     @watermark
--         * The watermark of the entry
--     @cleanupAfter
--         * The next date time to attempt cleanup
--
-- RETURN VALUE
--     The retry count.
--
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.IncrementDeletedInstanceRetryV2(
    @partitionName      VARCHAR(64),
    @studyInstanceUid   VARCHAR(64),
    @seriesInstanceUid  VARCHAR(64),
    @sopInstanceUid     VARCHAR(64),
    @watermark          BIGINT,
    @cleanupAfter       DATETIMEOFFSET(0)
)
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @retryCount INT

    UPDATE  dbo.DeletedInstance
    SET     @retryCount = RetryCount = RetryCount + 1,
            CleanupAfter = @cleanupAfter
    WHERE   PartitionName = @partitionName
        AND     StudyInstanceUid = @studyInstanceUid
        AND     SeriesInstanceUid = @seriesInstanceUid
        AND     SopInstanceUid = @sopInstanceUid
        AND     Watermark = @watermark

    SELECT @retryCount
END
GO

/***************************************************************************************/
-- STORED PROCEDURE
--    Index instance V3
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--    Adds or updates the various extended query tag indices for a given DICOM instance.
--
-- PARAMETERS
--     @watermark
--         * The Dicom instance watermark.
--     @stringExtendedQueryTags
--         * String extended query tag data
--     @longExtendedQueryTags
--         * Long extended query tag data
--     @doubleExtendedQueryTags
--         * Double extended query tag data
--     @dateTimeExtendedQueryTags
--         * DateTime extended query tag data
--     @personNameExtendedQueryTags
--         * PersonName extended query tag data
-- RETURN VALUE
--     None
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.IndexInstanceV3
    @watermark                                                                   BIGINT,
    @stringExtendedQueryTags dbo.InsertStringExtendedQueryTagTableType_1         READONLY,
    @longExtendedQueryTags dbo.InsertLongExtendedQueryTagTableType_1             READONLY,
    @doubleExtendedQueryTags dbo.InsertDoubleExtendedQueryTagTableType_1         READONLY,
    @dateTimeExtendedQueryTags dbo.InsertDateTimeExtendedQueryTagTableType_2     READONLY,
    @personNameExtendedQueryTags dbo.InsertPersonNameExtendedQueryTagTableType_1 READONLY
AS
BEGIN
    SET NOCOUNT    ON
    SET XACT_ABORT ON
    BEGIN TRANSACTION

        DECLARE @partitionKey INT
        DECLARE @studyKey BIGINT
        DECLARE @seriesKey BIGINT
        DECLARE @instanceKey BIGINT

        -- Add lock so that the instance cannot be removed
        DECLARE @status TINYINT
        SELECT
            @partitionKey = PartitionKey,
            @studyKey = StudyKey,
            @seriesKey = SeriesKey,
            @instanceKey = InstanceKey,
            @status = Status
        FROM dbo.Instance WITH (HOLDLOCK)
        WHERE Watermark = @watermark

        IF @@ROWCOUNT = 0
            THROW 50404, 'Instance does not exists', 1
        IF @status <> 1 -- Created
            THROW 50409, 'Instance has not yet been stored succssfully', 1

        -- Insert Extended Query Tags

        -- String Key tags
        IF EXISTS (SELECT 1 FROM @stringExtendedQueryTags)
        BEGIN
            MERGE INTO dbo.ExtendedQueryTagString WITH (HOLDLOCK) AS T
            USING
            (
                -- Locks tags in dbo.ExtendedQueryTag
                SELECT input.TagKey, input.TagValue, input.TagLevel
                FROM @stringExtendedQueryTags input
                INNER JOIN dbo.ExtendedQueryTag WITH (REPEATABLEREAD)
                ON dbo.ExtendedQueryTag.TagKey = input.TagKey
                -- Only merge on extended query tag which is being adding.
                AND dbo.ExtendedQueryTag.TagStatus <> 2
            ) AS S
            ON T.TagKey = S.TagKey
                AND T.PartitionKey = @partitionKey
                AND T.StudyKey = @studyKey
                -- Null SeriesKey indicates a Study level tag, no need to compare SeriesKey
                AND ISNULL(T.SeriesKey, @seriesKey) = @seriesKey
                -- Null InstanceKey indicates a Study/Series level tag, no to compare InstanceKey
                AND ISNULL(T.InstanceKey, @instanceKey) = @instanceKey
            WHEN MATCHED THEN
                -- When index already exist, update only when watermark is newer
                UPDATE SET T.Watermark = IIF(@watermark > T.Watermark, @watermark, T.Watermark), T.TagValue = IIF(@watermark > T.Watermark, S.TagValue, T.TagValue)
            WHEN NOT MATCHED THEN
                INSERT (TagKey, TagValue, PartitionKey, StudyKey, SeriesKey, InstanceKey, Watermark)
                VALUES
                (
                    S.TagKey,
                    S.TagValue,
                    @partitionKey,
                    @studyKey,
                    -- When TagLevel is not Study, we should fill SeriesKey
                    (CASE WHEN S.TagLevel <> 2 THEN @seriesKey ELSE NULL END),
                    -- When TagLevel is Instance, we should fill InstanceKey
                    (CASE WHEN S.TagLevel = 0 THEN @instanceKey ELSE NULL END),
                    @watermark
                );
        END

        -- Long Key tags
        IF EXISTS (SELECT 1 FROM @longExtendedQueryTags)
        BEGIN
            MERGE INTO dbo.ExtendedQueryTagLong WITH (HOLDLOCK) AS T
            USING
            (
                SELECT input.TagKey, input.TagValue, input.TagLevel
                FROM @longExtendedQueryTags input
                INNER JOIN dbo.ExtendedQueryTag WITH (REPEATABLEREAD)
                ON dbo.ExtendedQueryTag.TagKey = input.TagKey
                AND dbo.ExtendedQueryTag.TagStatus <> 2
            ) AS S
            ON T.TagKey = S.TagKey
                AND T.PartitionKey = @partitionKey
                AND T.StudyKey = @studyKey
                AND ISNULL(T.SeriesKey, @seriesKey) = @seriesKey
                AND ISNULL(T.InstanceKey, @instanceKey) = @instanceKey
            WHEN MATCHED THEN
                 -- When index already exist, update only when watermark is newer
                UPDATE SET T.Watermark = IIF(@watermark > T.Watermark, @watermark, T.Watermark), T.TagValue = IIF(@watermark > T.Watermark, S.TagValue, T.TagValue)
            WHEN NOT MATCHED THEN
                INSERT (TagKey, TagValue, PartitionKey, StudyKey, SeriesKey, InstanceKey, Watermark)
                VALUES
                (
                    S.TagKey,
                    S.TagValue,
                    @partitionKey,
                    @studyKey,
                    (CASE WHEN S.TagLevel <> 2 THEN @seriesKey ELSE NULL END),
                    (CASE WHEN S.TagLevel = 0 THEN @instanceKey ELSE NULL END),
                    @watermark
                );
        END

        -- Double Key tags
        IF EXISTS (SELECT 1 FROM @doubleExtendedQueryTags)
        BEGIN
            MERGE INTO dbo.ExtendedQueryTagDouble WITH (HOLDLOCK) AS T
            USING
            (
                SELECT input.TagKey, input.TagValue, input.TagLevel
                FROM @doubleExtendedQueryTags input
                INNER JOIN dbo.ExtendedQueryTag WITH (REPEATABLEREAD)
                ON dbo.ExtendedQueryTag.TagKey = input.TagKey
                AND dbo.ExtendedQueryTag.TagStatus <> 2
            ) AS S
            ON T.TagKey = S.TagKey
                AND T.PartitionKey = @partitionKey
                AND T.StudyKey = @studyKey
                AND ISNULL(T.SeriesKey, @seriesKey) = @seriesKey
                AND ISNULL(T.InstanceKey, @instanceKey) = @instanceKey
            WHEN MATCHED THEN
                -- When index already exist, update only when watermark is newer
                UPDATE SET T.Watermark = IIF(@watermark > T.Watermark, @watermark, T.Watermark), T.TagValue = IIF(@watermark > T.Watermark, S.TagValue, T.TagValue)
            WHEN NOT MATCHED THEN
              INSERT (TagKey, TagValue, PartitionKey, StudyKey, SeriesKey, InstanceKey, Watermark)
                VALUES
                (
                    S.TagKey,
                    S.TagValue,
                    @partitionKey,
                    @studyKey,
                    (CASE WHEN S.TagLevel <> 2 THEN @seriesKey ELSE NULL END),
                    (CASE WHEN S.TagLevel = 0 THEN @instanceKey ELSE NULL END),
                    @watermark
                );
        END

        -- DateTime Key tags
        IF EXISTS (SELECT 1 FROM @dateTimeExtendedQueryTags)
        BEGIN
            MERGE INTO dbo.ExtendedQueryTagDateTime WITH (HOLDLOCK) AS T
            USING
            (
                SELECT input.TagKey, input.TagValue, input.TagValueUtc, input.TagLevel
                FROM @dateTimeExtendedQueryTags input
                INNER JOIN dbo.ExtendedQueryTag WITH (REPEATABLEREAD)
                ON dbo.ExtendedQueryTag.TagKey = input.TagKey
                AND dbo.ExtendedQueryTag.TagStatus <> 2
            ) AS S
            ON T.TagKey = S.TagKey
                AND T.PartitionKey = @partitionKey
                AND T.StudyKey = @studyKey
                AND ISNULL(T.SeriesKey, @seriesKey) = @seriesKey
                AND ISNULL(T.InstanceKey, @instanceKey) = @instanceKey
            WHEN MATCHED THEN
                 -- When index already exist, update only when watermark is newer
                UPDATE SET T.Watermark = IIF(@watermark > T.Watermark, @watermark, T.Watermark), T.TagValue = IIF(@watermark > T.Watermark, S.TagValue, T.TagValue)
            WHEN NOT MATCHED THEN
               INSERT (TagKey, TagValue, PartitionKey, StudyKey, SeriesKey, InstanceKey, Watermark, TagValueUtc)
                VALUES
                (
                    S.TagKey,
                    S.TagValue,
                    @partitionKey,
                    @studyKey,
                    (CASE WHEN S.TagLevel <> 2 THEN @seriesKey ELSE NULL END),
                    (CASE WHEN S.TagLevel = 0 THEN @instanceKey ELSE NULL END),
                    @watermark,
                    S.TagValueUtc
                );
        END

        -- PersonName Key tags
        IF EXISTS (SELECT 1 FROM @personNameExtendedQueryTags)
        BEGIN
            MERGE INTO dbo.ExtendedQueryTagPersonName WITH (HOLDLOCK) AS T
            USING
            (
                SELECT input.TagKey, input.TagValue, input.TagLevel
                FROM @personNameExtendedQueryTags input
                INNER JOIN dbo.ExtendedQueryTag WITH (REPEATABLEREAD)
                ON dbo.ExtendedQueryTag.TagKey = input.TagKey
                AND dbo.ExtendedQueryTag.TagStatus <> 2
            ) AS S
            ON T.TagKey = S.TagKey
                AND T.PartitionKey = @partitionKey
                AND T.StudyKey = @studyKey
                AND ISNULL(T.SeriesKey, @seriesKey) = @seriesKey
                AND ISNULL(T.InstanceKey, @instanceKey) = @instanceKey
            WHEN MATCHED THEN
                -- When index already exist, update only when watermark is newer
                UPDATE SET T.Watermark = IIF(@watermark > T.Watermark, @watermark, T.Watermark), T.TagValue = IIF(@watermark > T.Watermark, S.TagValue, T.TagValue)
            WHEN NOT MATCHED THEN
               INSERT (TagKey, TagValue, PartitionKey, StudyKey, SeriesKey, InstanceKey, Watermark)
                VALUES
                (
                    S.TagKey,
                    S.TagValue,
                    @partitionKey,
                    @studyKey,
                    (CASE WHEN S.TagLevel <> 2 THEN @seriesKey ELSE NULL END),
                    (CASE WHEN S.TagLevel = 0 THEN @instanceKey ELSE NULL END),
                    @watermark
                );
        END

    COMMIT TRANSACTION
END
GO

/***************************************************************************************/
-- STORED PROCEDURE
--     RetrieveDeletedInstanceV2
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Retrieves deleted instances where the cleanupAfter is less than the current date in and the retry count hasn't been exceeded
--
-- PARAMETERS
--     @count
--         * The number of entries to return
--     @maxRetries
--         * The maximum number of times to retry a cleanup
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.RetrieveDeletedInstanceV2
    @count          INT,
    @maxRetries     INT
AS
BEGIN
    SET NOCOUNT ON

    SELECT  TOP (@count) PartitionName, StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, Watermark
    FROM    dbo.DeletedInstance WITH (UPDLOCK, READPAST)
    WHERE   RetryCount <= @maxRetries
    AND     CleanupAfter < SYSUTCDATETIME()
END
GO

/*************************************************************
    Stored procedures for updating an instance status.
**************************************************************/
--
-- STORED PROCEDURE
--     UpdateInstanceStatusV2
--
-- FIRST SCHEMA VERSION
--     6
--
-- DESCRIPTION
--     Updates a DICOM instance status.
--
-- PARAMETERS
--     @partitionName
--         * The client-provided data partition name.
--     @studyInstanceUid
--         * The study instance UID.
--     @seriesInstanceUid
--         * The series instance UID.
--     @sopInstanceUid
--         * The SOP instance UID.
--     @watermark
--         * The watermark.
--     @status
--         * The new status to update to.
--
-- RETURN VALUE
--     None
--
CREATE OR ALTER PROCEDURE dbo.UpdateInstanceStatusV2
    @partitionName      VARCHAR(64),
    @studyInstanceUid   VARCHAR(64),
    @seriesInstanceUid  VARCHAR(64),
    @sopInstanceUid     VARCHAR(64),
    @watermark          BIGINT,
    @status             TINYINT
AS
BEGIN
    SET NOCOUNT ON

    SET XACT_ABORT ON
    BEGIN TRANSACTION

    DECLARE @currentDate DATETIME2(7) = SYSUTCDATETIME()

    UPDATE dbo.Instance
    SET Status = @status, LastStatusUpdatedDate = @currentDate
    WHERE PartitionName = @partitionName
        AND StudyInstanceUid = @studyInstanceUid
        AND SeriesInstanceUid = @seriesInstanceUid
        AND SopInstanceUid = @sopInstanceUid
        AND Watermark = @watermark

    IF @@ROWCOUNT = 0
        -- The instance does not exist. Perhaps it was deleted?
        THROW 50404, 'Instance does not exist', 1;
    
    -- Insert to change feed.
    -- Currently this procedure is used only updating the status to created
    -- If that changes an if condition is needed.
    INSERT INTO dbo.ChangeFeed
        (Timestamp, Action, PartitionName, StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, OriginalWatermark)
    VALUES
        (@currentDate, 0, @partitionName, @studyInstanceUid, @seriesInstanceUid, @sopInstanceUid, @watermark)

    -- Update existing instance currentWatermark to latest
    UPDATE dbo.ChangeFeed
    SET CurrentWatermark      = @watermark
    WHERE PartitionName = @partitionName
        AND StudyInstanceUid    = @studyInstanceUid
        AND SeriesInstanceUid = @seriesInstanceUid
        AND SopInstanceUid    = @sopInstanceUid

    COMMIT TRANSACTION
END
GO 

COMMIT TRANSACTION

/*************************************************************
Drop Study fulltext index outside transaction
**************************************************************/

IF EXISTS (
    SELECT i.name
    FROM sys.indexes i
    JOIN sys.fulltext_indexes fi
        ON (i.index_id = fi.unique_index_id)
    WHERE i.name = 'IXC_Study'
        AND i.object_id = OBJECT_ID('dbo.Study'))
BEGIN
    -- This index uses IXC_Study as it's unique index, so must be dropped first.
    -- We'll restore the fulltext index with a new unique index after this transaction.
    DROP FULLTEXT INDEX ON dbo.Study    
END
GO

/*************************************************************
    Indexes
**************************************************************/
SET XACT_ABORT ON
BEGIN TRANSACTION

/*******************        Study       **********************/
IF EXISTS 
(
    SELECT *
    FROM    sys.indexes
    WHERE   NAME = 'IX_Study_StudyInstanceUid'
        AND Object_id = OBJECT_ID('dbo.Study')
)
BEGIN
    CREATE UNIQUE CLUSTERED INDEX IXC_Study ON dbo.Study
    (
        PartitionKey,
        StudyKey
    )
    WITH
    (
        DROP_EXISTING = ON,
        ONLINE = ON
    )

    DROP INDEX IX_Study_StudyInstanceUid ON dbo.Study

    CREATE UNIQUE NONCLUSTERED INDEX IX_Study_PartitionKey_StudyInstanceUid ON dbo.Study
    (
        PartitionKey,
        StudyInstanceUid
    ) WITH (DATA_COMPRESSION = PAGE)
END
GO

/*******************        Series       **********************/
IF EXISTS 
(
    SELECT *
    FROM    sys.indexes
    WHERE   NAME = 'IX_Series_SeriesInstanceUid'
        AND Object_id = OBJECT_ID('dbo.Series')
)
BEGIN
    CREATE UNIQUE CLUSTERED INDEX IXC_Series ON dbo.Series
    (
        PartitionKey,
        StudyKey,
        SeriesKey
    )
    WITH
    (
        DROP_EXISTING = ON,
        ONLINE = ON
    )

    DROP INDEX IX_Series_SeriesInstanceUid ON dbo.Series

    CREATE UNIQUE NONCLUSTERED INDEX IX_Series_StudyKey_SeriesInstanceUid ON dbo.Series
    (
        StudyKey,
        SeriesInstanceUid
    ) WITH (DATA_COMPRESSION = PAGE)
END
GO

/*******************        Instance       **********************/

IF EXISTS 
(
    SELECT *
    FROM    sys.indexes
    WHERE   NAME = 'IX_Instance_StudyInstanceUid_SeriesInstanceUid_SopInstanceUid'
        AND Object_id = OBJECT_ID('dbo.Instance')
)
BEGIN
    DROP INDEX IX_Instance_StudyInstanceUid_SeriesInstanceUid_SopInstanceUid ON dbo.Instance

    CREATE UNIQUE NONCLUSTERED INDEX IX_Instance_PartitionName_StudyInstanceUid_SeriesInstanceUid_SopInstanceUid ON dbo.Instance
    (
        PartitionName,
        StudyInstanceUid,
        SeriesInstanceUid,
        SopInstanceUid
    ) WITH (DATA_COMPRESSION = PAGE)

    DROP INDEX IX_Instance_StudyInstanceUid_Status ON dbo.Instance

    CREATE NONCLUSTERED INDEX IX_Instance_PartitionName_StudyInstanceUid_Status ON dbo.Instance
    (
        PartitionName,
        StudyInstanceUid,
        Status
    ) WITH (DATA_COMPRESSION = PAGE)

    DROP INDEX IX_Instance_StudyInstanceUid_SeriesInstanceUid_Status ON dbo.Instance

    CREATE NONCLUSTERED INDEX IX_Instance_PartitionName_StudyInstanceUid_SeriesInstanceUid_Status ON dbo.Instance
    (
        PartitionName,
        StudyInstanceUid,
        SeriesInstanceUid,
        Status
    ) WITH (DATA_COMPRESSION = PAGE)

    DROP INDEX IX_Instance_SopInstanceUid_Status ON dbo.Instance

    CREATE NONCLUSTERED INDEX IX_Instance_PartitionName_SopInstanceUid_Status ON dbo.Instance
    (
        PartitionName,
        SopInstanceUid,
        Status
    ) WITH (DATA_COMPRESSION = PAGE)

    DROP INDEX IX_Instance_SeriesKey_Status ON dbo.Instance

    CREATE NONCLUSTERED INDEX IX_Instance_PartitionKey_SeriesKey_Status ON dbo.Instance
    (
        PartitionKey,
        SeriesKey,
        Status
    ) WITH (DATA_COMPRESSION = PAGE)

    DROP INDEX IX_Instance_StudyKey_Status ON dbo.Instance

    CREATE NONCLUSTERED INDEX IX_Instance_PartitionKey_StudyKey_Status ON dbo.Instance
    (
        PartitionKey,
        StudyKey,
        Status
    ) WITH (DATA_COMPRESSION = PAGE)
END
GO

/*******************       ChangeFeed      **********************/
IF EXISTS 
(
    SELECT *
    FROM    sys.indexes
    WHERE   NAME = 'IX_ChangeFeed_StudyInstanceUid_SeriesInstanceUid_SopInstanceUid'
        AND Object_id = OBJECT_ID('dbo.ChangeFeed')
)
BEGIN
    DROP INDEX IX_ChangeFeed_StudyInstanceUid_SeriesInstanceUid_SopInstanceUid ON dbo.ChangeFeed

    CREATE NONCLUSTERED INDEX IX_ChangeFeed_PartitionName_StudyInstanceUid_SeriesInstanceUid_SopInstanceUid ON dbo.ChangeFeed
    (
        PartitionName,
        StudyInstanceUid,
        SeriesInstanceUid,
        SopInstanceUid
    ) WITH (DATA_COMPRESSION = PAGE)
END
GO

/***************        DeletedInstance       *******************/
SELECT ic.index_column_id 
FROM sys.indexes i
JOIN sys.index_columns ic
    ON i.index_id = ic.index_id
WHERE i.name = 'IXC_DeletedInstance'
    AND ic.object_id = OBJECT_ID('dbo.DeletedInstance')

IF @@ROWCOUNT < 5
BEGIN
   CREATE UNIQUE CLUSTERED INDEX IXC_DeletedInstance ON dbo.DeletedInstance
    (
        PartitionName,
        StudyInstanceUid,
        SeriesInstanceUid,
        SopInstanceUid,
        Watermark
    ) 
    WITH
    (
        DROP_EXISTING = ON,
        ONLINE = ON
    )
END
GO

/***********        ExtendedQueryTagDateTime       **************/

SELECT ic.index_column_id
FROM sys.indexes i
JOIN sys.index_columns ic
    ON i.index_id = ic.index_id
WHERE i.name = 'IXC_ExtendedQueryTagDateTime'
    AND ic.object_id = OBJECT_ID('dbo.ExtendedQueryTagDateTime')

IF @@ROWCOUNT < 6
BEGIN
    CREATE UNIQUE CLUSTERED INDEX IXC_ExtendedQueryTagDateTime ON dbo.ExtendedQueryTagDateTime
    (
        TagKey,
        TagValue,
        PartitionKey,
        StudyKey,
        SeriesKey,
        InstanceKey
    ) 
    WITH
    (
        DROP_EXISTING = ON,
        ONLINE = ON
    )
END
GO

/************        ExtendedQueryTagDouble       ***************/

SELECT ic.index_column_id
FROM sys.indexes i
JOIN sys.index_columns ic
    ON i.index_id = ic.index_id
WHERE i.name = 'IXC_ExtendedQueryTagDouble'
    AND ic.object_id = OBJECT_ID('dbo.ExtendedQueryTagDouble')

IF @@ROWCOUNT < 6
BEGIN
    CREATE UNIQUE CLUSTERED INDEX IXC_ExtendedQueryTagDouble ON dbo.ExtendedQueryTagDouble
    (
        TagKey,
        TagValue,
        PartitionKey,
        StudyKey,
        SeriesKey,
        InstanceKey
    ) 
    WITH
    (
        DROP_EXISTING = ON,
        ONLINE = ON
    )
END
GO

/*************        ExtendedQueryTagLong       ****************/

SELECT ic.index_column_id
FROM sys.indexes i
JOIN sys.index_columns ic
    ON i.index_id = ic.index_id
WHERE i.name = 'IXC_ExtendedQueryTagLong'
    AND ic.object_id = OBJECT_ID('dbo.ExtendedQueryTagLong')

IF @@ROWCOUNT < 6
BEGIN
    
    CREATE UNIQUE CLUSTERED INDEX IXC_ExtendedQueryTagLong ON dbo.ExtendedQueryTagLong
    (
        TagKey,
        TagValue,
        PartitionKey,
        StudyKey,
        SeriesKey,
        InstanceKey
    ) 
    WITH
    (
        DROP_EXISTING = ON,
        ONLINE = ON
    )
END
GO

/**********        ExtendedQueryTagPersonName       *************/

SELECT ic.index_column_id
FROM sys.indexes i
JOIN sys.index_columns ic
    ON i.index_id = ic.index_id
WHERE i.name = 'IXC_ExtendedQueryTagPersonName'
    AND ic.object_id = OBJECT_ID('dbo.ExtendedQueryTagPersonName')

IF @@ROWCOUNT < 6
BEGIN
        CREATE UNIQUE CLUSTERED INDEX IXC_ExtendedQueryTagPersonName ON dbo.ExtendedQueryTagPersonName
    (
        TagKey,
        TagValue,
        PartitionKey,
        StudyKey,
        SeriesKey,
        InstanceKey
    ) 
    WITH
    (
        DROP_EXISTING = ON,
        ONLINE = ON
    )
END
GO

/************        ExtendedQueryTagString       ***************/

SELECT ic.index_column_id
FROM sys.indexes i
JOIN sys.index_columns ic
    ON i.index_id = ic.index_id
WHERE i.name = 'IXC_ExtendedQueryTagString'
    AND ic.object_id = OBJECT_ID('dbo.ExtendedQueryTagString')

IF @@ROWCOUNT < 6
BEGIN
    
    CREATE UNIQUE CLUSTERED INDEX IXC_ExtendedQueryTagString ON dbo.ExtendedQueryTagString
    (
        TagKey,
        TagValue,
        PartitionKey,
        StudyKey,
        SeriesKey,
        InstanceKey
    ) 
    WITH
    (
        DROP_EXISTING = ON,
        ONLINE = ON
    )
END
GO

COMMIT TRANSACTION

/*************************************************************
Full text catalog and index creation outside transaction
**************************************************************/

IF EXISTS (
    SELECT i.name
    FROM sys.indexes i
    JOIN sys.fulltext_indexes fi
        ON (i.index_id = fi.unique_index_id)
    WHERE i.name = 'IXC_Study'
        AND i.object_id = OBJECT_ID('dbo.Study'))
BEGIN
    CREATE FULLTEXT INDEX ON Study(PatientNameWords, ReferringPhysicianNameWords LANGUAGE 1033)
    KEY INDEX IX_Study_StudyKey
    WITH STOPLIST = OFF;
END
GO