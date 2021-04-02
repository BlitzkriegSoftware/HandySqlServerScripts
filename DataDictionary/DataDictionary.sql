	-- -----------------------------------------------------
	-- Data Dictionary
	-- Version 1.4
	-- Produces Data Dictionary fOR Current DatabASe
	-- -----------------------------------------------------

	-- Definitions
	SET NOCOUNT ON;

	DECLARE 
		@TableName NVARCHAR(max)
	  , @TableName2 NVARCHAR(max)
	  , @ColumnName  VARCHAR(max)
	  , @ColumnName2  VARCHAR(max)
	  , @ColumnType VARCHAR(max)
	  , @ColumnType2 VARCHAR(max)
	  , @MaxLength INT
	  , @MaxLength2 INT
	  , @IsNULLable TINYINT
	  , @IsNULLable2 TINYINT
	  , @Description VARCHAR(max)
	  , @HASMismatch TINYINT;

	DECLARE @DataDictionary TABLE 
	(
		TableName VARCHAR(max)
	  , TableDescription  VARCHAR(max)
	  , ColumnName  VARCHAR(max)
	  , ColumnDescription  VARCHAR(max)
	  , IndexCount INT
	  , FKCount INT
	  , ColumnType VARCHAR(max)
	  , MaxLength INT
	  , Pecision INT
	  , Scale INT
	  , IsNULLable TINYINT
	  , IsComputed TINYINT
	  , DefaultValue VARCHAR(max)	
	)

	DECLARE @TableXRef TABLE 
	(
		TableNames  VARCHAR(max)
	  , ColumnName  VARCHAR(max)
	  , ColumnType  VARCHAR(max)
	  , MaxLength   INT
	  , IsNULLable  TINYINT
	  , HASMismatch TINYINT
	)

	-- -----------------------------------------------------
	-- Compute Data Dictionary
	-- -----------------------------------------------------

	DECLARE Tbls CURSOR 
	FOR

	SELECT DISTINCT Table_name
	FROM INFORMATION_SCHEMA.COLUMNS
	--put any exclusions here
	--WHERE table_name not like '%old' 
	ORDER BY Table_name;

	OPEN Tbls
	FETCH NEXT FROM Tbls
	INTO @TableName

	WHILE @@FETCH_STATUS = 0
	BEGIN

		SELECT @Description = CAST(Value AS VARCHAR(max)) FROM 
		sys.extENDed_properties A
		WHERE A.majOR_id = OBJECT_ID(@TableName)
		AND name = 'MS_Description' AND minOR_id = 0;

		INSERT INTO @DataDictionary (TableName, TableDescription, ColumnName, ColumnDescription, IndexCount, FKCount, ColumnType, MaxLength, Pecision, Scale, IsNULLable, IsComputed, DefaultValue)
		SELECT
			  @TableName AS 'Table'
			, @Description AS 'Description'
			, clmns.name
			, ISNULL(CAST(exprop.value AS VARCHAR(max)) , '') AS 'Value'
			, ISNULL(idxcol.index_column_id, 0) AS 'Index'
			, ISNULL((SELECT TOP 1 1 FROM sys.fOReign_key_columns AS fkclmn WHERE fkclmn.parent_column_id = clmns.column_id AND fkclmn.parent_object_id = clmns.object_id ), 0) AS 'FK'
			, udt.name
			, CASE WHEN typ.name IN (N'nchar', N'NVARCHAR') AND clmns.max_length <> -1 THEN clmns.max_length/2 ELSE clmns.max_length END  AS 'Max Length'
			, clmns.precision 
			, clmns.scale 
			, clmns.is_Nullable 
			, clmns.is_computed 
			, cnstr.definition 
			FROM sys.tables AS tbl
			INNER JOIN sys.all_columns AS clmns
			ON clmns.object_id=tbl.object_id
			LEFT OUTER JOIN sys.indexes AS idx
			ON idx.object_id = clmns.object_id AND 1 =idx.is_primary_key
			LEFT OUTER JOIN sys.index_columns AS idxcol
			ON idxcol.index_id = idx.index_id AND idxcol.column_id = clmns.column_id AND idxcol.object_id = clmns.object_id AND 0 = idxcol.is_included_column
			LEFT OUTER JOIN sys.types AS udt
			ON udt.user_type_id = clmns.user_type_id
			LEFT OUTER JOIN sys.types AS typ
			ON typ.user_type_id = clmns.system_type_id AND typ.user_type_id = typ.system_type_id
			LEFT JOIN sys.default_constraINTs AS cnstr
			ON cnstr.object_id=clmns.default_object_id
			LEFT OUTER JOIN sys.extENDed_properties exprop
			ON exprop.majOR_id = clmns.object_id AND exprop.minOR_id = clmns.column_id AND exprop.name = 'MS_Description'
			WHERE (tbl.name = @TableName) 
				-- AND (exprop.clASs = 1) --I don't want to include comments on indexes
			ORDER BY clmns.column_id ASC;

	FETCH NEXT FROM Tbls
	INTO @TableName
	END

	CLOSE Tbls
	DEALLOCATE Tbls

	-- Show repORt

	SELECT 
		TableName
	  , ISNULL(TableDescription,'') TableDescription
	  , ColumnName 
	  , ColumnDescription
	  , ColumnType 
	  , MaxLength 
	  , Pecision 
	  , Scale 
	  , IsNullable 
	  , ISNULL(DefaultValue , '') DefaultValue
	 FROM @DataDictionary
	 ORDER BY ColumnName, TableName;

	-- -------------------
	-- Produce XREF
	-- -------------------

	DECLARE Tbls CURSOR 
	FOR
		SELECT 
		    TableName
		  ,	ColumnName
		  , ColumnType 
		  , MaxLength 
		  , IsNULLable 
		FROM
			@DataDictionary
		ORDER BY ColumnName;

	OPEN Tbls

	FETCH NEXT FROM Tbls
	INTO 
		    @TableName
		  ,	@ColumnName
		  , @ColumnType 
		  , @MaxLength 
		  , @IsNULLable 

	WHILE @@FETCH_STATUS = 0
	BEGIN

		-- PRINT 'Column: ' + @ColumnName + 'Table: ' + @TableName

		SET @ColumnName2 = NULL;

		SELECT 
			  @ColumnName2 = ColumnName
			, @TableName2 = TableNames
			, @MaxLength2 = MaxLength
			, @IsNULLable2 = IsNULLable
		FROM
			@TableXRef
		WHERE 
			(ColumnName = @ColumnName);
		
		-- PRINT '>Column2: ' + IsNULL(@ColumnName2, '(NULL)')
		
		IF(@ColumnName2 IS NULL)
		BEGIN
			INSERT INTO @TableXRef (TableNames, ColumnName,  ColumnType,  MaxLength,  IsNULLable, HASMismatch)
			VALUES                (@TableName, @ColumnName, @ColumnType, @MaxLength, @IsNULLable, 0);
			-- PRINT '>>INSERT'
		END
		ELSE
		BEGIN
			IF((@ColumnType <> @ColumnType2) OR (@MaxLength <> @MaxLength2) OR (@IsNULLable <> @IsNULLable2))
			BEGIN
				UPDATE @TableXRef 
				SET TableNames = @TableName2 + ', ' + @TableName, HASMisMatch = 1
				WHERE (ColumnName = @ColumnName);
				-- PRINT '>>Mismatch'
			END
			ELSE
			BEGIN
			UPDATE @TableXRef 
				SET TableNames = @TableName2 + ', ' + @TableName 
				WHERE (ColumnName = @ColumnName);
				-- PRINT '>>Match'
			END
		END

	FETCH NEXT FROM Tbls
		INTO 
		    @TableName
		  ,	@ColumnName
		  , @ColumnType 
		  , @MaxLength 
		  , @IsNULLable

	END

	CLOSE Tbls;
	DEALLOCATE Tbls;

-- RepORt on Cross Reference

	SELECT 
		  ColumnName
		, TableNames 
		, HASMisMatch
	FROM @TableXRef 
	--WHERE HASMisMatch = 1
	ORDER BY ColumnName;