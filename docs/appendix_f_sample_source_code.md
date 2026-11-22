# Appendix F – Sample Source Code

## Introduction

This appendix presents selected excerpts from the existing CropCare AI project. The samples illustrate important mobile, AI, data-management, and administrative functions. They are taken from the source files identified below; they are not complete standalone programs. Supporting imports, models, helpers, and related code are omitted where noted. No credentials or private configuration values are included.

## F.1 User Registration and Sign-In

**Source File:** `lib/data/repositories/auth_repository.dart` (registration: lines 125–207; sign-in: lines 351–396)

**Description:** These repository methods create an account through the authentication service or sign in an existing user. They also save the resulting user profile in the local database.

**Sample Source Code:**

```dart
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required String emailRedirectTo,
    String? barangay,
    required String municipality,
    required String province,
    required String country,
  }) async {
    try {
      final response = await supabaseService.signUpWithEmail(
        email: email,
        password: password,
        fullName: fullName,
        emailRedirectTo: emailRedirectTo,
        barangay: barangay,
        municipality: municipality,
        province: province,
        country: country,
        legalAcceptedAt: DateTime.now(),
        termsVersion: AppConstants.termsVersion,
        privacyPolicyVersion: AppConstants.privacyPolicyVersion,
      );

      final supabaseUser = response.user;
      if (supabaseUser == null) {
        return const AuthResult(
          success: false,
          error: 'Registration failed. Please try again or verify your email.',
        );
      }

      final now = DateTime.now();
      final user = UserModel(
        id: supabaseUser.id,
        fullName: fullName,
        email: email,
        barangay: _cleanString(barangay),
        municipality: _cleanString(municipality),
        province: _cleanString(province),
        country: _cleanString(country),
        provider: 'email',
        createdAt: now,
        updatedAt: now,
      );

      // Cache locally
      await dbHelper.upsertUser(user.toMap());

      final hasAuthenticatedSession =
          response.session != null && supabaseService.isSignedIn;

      if (!hasAuthenticatedSession) {
        return const AuthResult(
          success: true,
          requiresEmailConfirmation: true,
          message:
              'Account created. Check your email for the verification link, then sign in.',
        );
      }

      await _ensureRemoteProfile(
        userId: supabaseUser.id,
        email: email,
        fullName: fullName,
        barangay: barangay,
        municipality: municipality,
        province: province,
        country: country,
      );

      return AuthResult(success: true, user: user);
    } on AuthException catch (e) {
      return AuthResult(success: false, error: e.message);
    } catch (_) {
      return const AuthResult(
        success: false,
        error:
            'Could not create your account. Check your internet connection and try again.',
      );
    }
  }

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await supabaseService.signInWithEmail(
        email: email,
        password: password,
      );

      final supabaseUser = response.user;
      if (supabaseUser == null) {
        return const AuthResult(success: false, error: 'Sign-in failed.');
      }

      var profile = await supabaseService.getProfile(supabaseUser.id);
      if (profile == null) {
        await _ensureRemoteProfile(
          userId: supabaseUser.id,
          email: supabaseUser.email ?? email,
          fullName: _cleanString(supabaseUser.userMetadata?['full_name']),
          avatarUrl: _cleanString(supabaseUser.userMetadata?['avatar_url']),
          barangay: _cleanString(supabaseUser.userMetadata?['barangay']),
          municipality:
              _cleanString(supabaseUser.userMetadata?['municipality']),
          province: _cleanString(supabaseUser.userMetadata?['province']),
          country: _cleanString(supabaseUser.userMetadata?['country']),
        );
        profile = await supabaseService.getProfile(supabaseUser.id);
      }

      final user = _buildUserModel(supabaseUser, profile: profile);

      await dbHelper.upsertUser(user.toMap());

      return AuthResult(success: true, user: user);
    } on AuthException catch (e) {
      return AuthResult(success: false, error: e.message);
    } catch (_) {
      return const AuthResult(
        success: false,
        error:
            'Could not sign in. Check your internet connection and try again.',
      );
    }
  }
```

**Explanation:** Registration sends account and location details to the authentication service, creates a local user record, and handles email confirmation when a session is not immediately available. Sign-in retrieves or creates the user profile and caches it locally. The excerpt depends on the Supabase service, database helper, models, and profile helper methods.

## F.2 Vegetable Scan and Crop-Family Handoff

**Source File:** `lib/features/scan/preview_screen.dart` (lines 56–85)

**Description:** This method checks that a crop family has been selected, then opens the diagnosis chat with the image and crop information.

**Sample Source Code:**

```dart
  Future<void> _continueToChat() async {
    if (_continuing) {
      return;
    }
    if (_selectedCropType == null) {
      setState(() => _cropSelectionError = true);
      _cropErrorController.forward(from: 0);
      return;
    }

    setState(() => _continuing = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScanResultScreen(
            imageFile: widget.imageFile,
            imageBytes: widget.imageBytes,
            initialQuery: _messageCtrl.text.trim(),
            cropTypeHint: _selectedCropType,
            openChatOnComplete: true,
            isFromVideo: widget.isFromVideo,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _continuing = false);
      }
    }
  }
```

**Explanation:** The method prevents duplicate navigation while a handoff is in progress. If no crop family is selected, it shows the selection error and does not continue. Otherwise, it passes the image, optional message, crop hint, and video flag to the diagnosis screen.

## F.3 Offline TFLite Image Classification

**Source File:** `lib/services/tflite_classifier_core.dart` (lines 21–83)

**Description:** This method prepares a selected image for the local TensorFlow Lite model, runs inference, and converts the model scores into the application's diagnosis response.

**Sample Source Code:**

```dart
  AiBackendDetectResponse classifyImage({
    required Uint8List imageBytes,
    required String filename,
    required Interpreter interpreter,
    required List<String> labels,
    String? cropType,
    String source = 'local-tflite',
    String modelName = 'cropcare_efficientnet_v2',
    String modelVersion = 'v2-subset-100',
    String? modelSource,
  }) {
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final inputShape = inputTensor.shape;
    validateModelContract(
      inputShape: inputShape,
      outputShape: outputTensor.shape,
      labelCount: labels.length,
    );
    final inputHeight = inputShape[1];
    final inputWidth = inputShape[2];
    final isUint8Input =
        inputTensor.type.toString().toLowerCase().contains('uint8');
    final isUint8Output =
        outputTensor.type.toString().toLowerCase().contains('uint8');

    final input = buildEfficientNetInputTensor(
      imageBytes: imageBytes,
      inputHeight: inputHeight,
      inputWidth: inputWidth,
      inputDtype:
          isUint8Input ? TfliteInputDtype.uint8 : TfliteInputDtype.float32,
    );

    final List<double> scores;
    if (isUint8Output) {
      final rawOutput = [List<int>.filled(labels.length, 0)];
      interpreter.run(input, rawOutput);
      final params = outputTensor.params;
      final scale = params.scale;
      final zeroPoint = params.zeroPoint;
      scores =
          rawOutput.first.map((value) => (value - zeroPoint) * scale).toList();
    } else {
      final rawOutput = [List<double>.filled(labels.length, 0.0)];
      interpreter.run(input, rawOutput);
      scores = rawOutput.first;
    }
    if (scores.isEmpty) {
      throw Exception('The TFLite model returned no predictions.');
    }

    return responseForScores(
      scores: scores,
      labels: labels,
      cropType: cropType,
      source: source,
      modelName: modelName,
      modelVersion: modelVersion,
      filename: filename,
      modelSource: modelSource,
    );
  }
```

**Explanation:** The method checks the model's input and output shapes, resizes and encodes the image using the expected input type, and runs the interpreter. It accounts for quantized output values before mapping scores and labels to a diagnosis response. Image preprocessing and score interpretation are implemented by helper methods not included here.

## F.4 Online AI Chat and Response Processing

**Source Files:** `lib/data/remote/ai_backend_service.dart` (lines 112–164); `ai_backend/app/services/llm_service.py` (lines 407–440 and 146–166)

**Description:** The Flutter service packages the user's message, diagnosis context, optional image data, and conversation history for the AI backend. The backend submits the request to the configured response API and can retry without web search if that option fails.

**Sample Source Code:**

```dart
  Future<AiBackendChatResponse> sendChatMessage({
    required String userMessage,
    String? cropId,
    DiagnosisModel? diagnosis,
    List<int>? imageBytes,
    List<List<int>> imageBytesList = const [],
    String? imageMimeType,
    List<Map<String, String>> conversationHistory = const [],
    String? locale,
    String? hintCropType,
    bool imagesFromPreviousTurns = false,
  }) async {
    final imageDataUrls = imageBytesList
        .where((bytes) => bytes.isNotEmpty)
        .map((bytes) => _buildImageDataUrl(bytes, mimeType: imageMimeType))
        .toList(growable: false);
    final payload = {
      'user_message': userMessage,
      if (cropId != null && cropId.isNotEmpty) 'crop_id': cropId,
      if (diagnosis != null)
        'diagnosis': {
          'crop_type': _inferDiagnosisCropType(diagnosis),
          'label_key': diagnosis.labelKey,
          'disease_name': diagnosis.diseaseName,
          'confidence': diagnosis.confidenceScore,
          'severity': diagnosis.severity.value,
        },
      if (imageDataUrls.isEmpty && imageBytes != null && imageBytes.isNotEmpty)
        'image_data_url': _buildImageDataUrl(
          imageBytes,
          mimeType: imageMimeType,
        ),
      if (imageDataUrls.isNotEmpty) 'image_data_urls': imageDataUrls,
      if (imagesFromPreviousTurns && imageDataUrls.isNotEmpty)
        'images_from_previous_turns': true,
      if (conversationHistory.isNotEmpty)
        'conversation_history': conversationHistory,
      if (locale != null && locale.isNotEmpty) 'locale': locale,
      if (hintCropType != null && hintCropType.trim().isNotEmpty)
        'hint_crop_type': hintCropType.trim().toLowerCase(),
    };
    final response = await _postJsonWithWarmup(
      path: '/v1/chat',
      payload: payload,
      timeout: const Duration(seconds: 20),
    );

    _throwIfError(response);

    return AiBackendChatResponse.fromMap(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
```

The backend sends the prompt and user content to the configured response API:

```python
    def _create_response(
        self,
        client: Any,
        *,
        system_prompt: str,
        user_content: list[dict[str, str]],
        allow_web_search: bool,
    ) -> tuple[Any, bool]:
        payload = [
            {
                "role": "system",
                "content": [{"type": "input_text", "text": system_prompt}],
            },
            {"role": "user", "content": user_content},
        ]

        if allow_web_search:
            try:
                response = client.responses.create(
                    model=self._settings.openai_model,
                    input=payload,
                    tools=[{"type": "web_search_preview"}],
                )
                return response, self._response_used_web_search(response)
            except Exception:
                logger.exception(
                    "OpenAI web search request failed. Retrying without web search."
                )

        response = client.responses.create(
            model=self._settings.openai_model,
            input=payload,
        )
        return response, False
```

The backend also separates a structured metadata footer from the user-facing answer:

```python
    def _split_ccai_json(self, raw_answer: str) -> tuple[str, dict[str, Any]]:
        text = (raw_answer or "").rstrip()
        if _CCAI_JSON_PREFIX not in text:
            return raw_answer, {}

        lines = text.split("\n")
        last_line = lines[-1].strip() if lines else ""
        if not last_line.startswith(_CCAI_JSON_PREFIX):
            return raw_answer, {}

        json_part = last_line[len(_CCAI_JSON_PREFIX) :].strip()
        try:
            meta = json.loads(json_part)
            if not isinstance(meta, dict):
                return raw_answer, {}
        except json.JSONDecodeError:
            logger.warning("Could not parse CCAI_JSON footer; using empty metadata.")
            return raw_answer, {}

        body = "\n".join(lines[:-1]).rstrip()
        return body, meta
```

**Explanation:** The client includes available crop and conversation context with the request and parses the backend response into the app's chat response model. The backend constructs the system/user payload, optionally requests web search, and removes a valid JSON footer from the answer text. Image encoding, HTTP transport, prompt construction, and response schemas are handled elsewhere.

## F.5 Local Data Storage and Sync Queue

**Source File:** `lib/data/local/database_helper.dart` (lines 556–610)

**Description:** These methods save local records and queue their corresponding remote upserts in one SQLite transaction, then retrieve pending queue entries for synchronization.

**Sample Source Code:**

```dart
  /// Commits related local rows and all of their sync queue entries atomically.
  /// Existing row IDs are retained so replaying the queued upserts is idempotent.
  Future<void> upsertRowsAndQueue(
    Iterable<LocalSyncUpsert> writes,
  ) async {
    if (_isDisabledOnPlatform) return;
    final items = writes.toList(growable: false);
    if (items.isEmpty) return;

    final db = await database;
    final queuedAt = DateTime.now().toIso8601String();
    await db.transaction((transaction) async {
      for (final write in items) {
        await transaction.insert(
          write.tableName,
          _normalizeSqliteRow(write.localData),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        // Keep only the newest pending upsert for a record. Deleting the old
        // queue row (rather than updating it) is safe when an earlier sync is
        // interrupted: its completion cannot accidentally delete this new row.
        await transaction.delete(
          AppConstants.syncQueueTable,
          where: 'table_name = ? AND record_id = ? AND operation = ?',
          whereArgs: [write.tableName, write.recordId, 'UPSERT'],
        );
        await transaction.insert(AppConstants.syncQueueTable, {
          'table_name': write.tableName,
          'record_id': write.recordId,
          'operation': 'UPSERT',
          'payload': jsonEncode(write.remoteData),
          'created_at': queuedAt,
          'attempts': 0,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    if (_isDisabledOnPlatform) return [];
    final db = await database;
    return db.query(
      AppConstants.syncQueueTable,
      columns: const [
        'id',
        'table_name',
        'record_id',
        'operation',
        'created_at',
        'attempts',
        'last_error',
      ],
      orderBy: 'created_at ASC, id ASC',
    );
  }
```

**Explanation:** Related local writes and queue entries are committed atomically, so a saved local change is paired with a pending synchronization item. The queue reader returns pending items in creation order. Database setup, row normalization, and the `LocalSyncUpsert` type are not shown.

## F.6 Crop Progress, Daily Tasks, and Sync Handoff

**Source Files:** `lib/features/crops/providers/crops_provider.dart` (lines 1359–1373); `lib/features/crops/screens/crop_detail_screen.dart` (lines 782–799); `lib/services/sync_service.dart` (lines 1090–1097)

**Description:** The excerpts show how crop progress is saved locally and queued, how a daily task completion updates the screen, and how pending writes are handed to the sync service.

**Sample Source Code:**

```dart
  Future<void> saveProgressUpdate(
    ProgressUpdateModel update, {
    bool syncNow = true,
  }) async {
    _error = null;
    await _upsertLocallyAndQueue(
      table: AppConstants.progressUpdatesTable,
      recordId: update.id,
      localData: update.toMap(),
      remoteData: update.toRemoteMap()..['is_deleted'] = update.isDeleted,
    );
    if (syncNow) {
      await _attemptSync();
    }
  }
```

```dart
  Future<void> _completeDailyTask(TreatmentTaskModel task) async {
    final completedTask = await context.read<CropsProvider>().markTaskDone(
          task.id,
          recomputeHealthScore: false,
          syncNow: false,
        );
    if (completedTask == null || !mounted) {
      return;
    }

    setState(() {
      _tasks = _tasks
          .map((currentTask) =>
              currentTask.id == completedTask.id ? completedTask : currentTask)
          .toList();
    });
    unawaited(context.read<CropsProvider>().flushPendingSync());
  }
```

```dart
  /// Persists local rows and their queue entries in one SQLite transaction.
  /// The revision change makes an already-active sync run drain this new batch.
  Future<void> persistQueuedUpserts(
    Iterable<LocalSyncUpsert> writes,
  ) async {
    final items = writes.toList(growable: false);
    if (items.isEmpty) return;
    await dbHelper.upsertRowsAndQueue(items);
    _queueRevision++;
  }
```

**Explanation:** Progress updates are written through the provider's local-and-queue path, with an option to attempt synchronization immediately. Completing a task updates the displayed task list and triggers a pending-sync flush. The sync service persists queued upserts and increments its queue revision. Other progress fields, such as any attached media, are managed by related screen and model code not shown here.

## F.7 Farm Vitality Health Score

**Source File:** `lib/services/health_score_service.dart` (lines 144–162, 203–233)

**Description:** The service computes a daily score from due tasks, completed tasks, and the latest diagnosis severity.

**Sample Source Code:**

```dart
  static int computeCurrentScore({
    required List<TreatmentTaskModel> tasks,
    required List<DiagnosisModel> diagnoses,
    required DateTime now,
  }) {
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final dueTasks =
        tasks.where((task) => !task.dueAt.isAfter(endOfToday)).toList();
    final completedTasks = dueTasks
        .where((task) =>
            task.completedAt != null && !task.completedAt!.isAfter(endOfToday))
        .toList();

    return _scoreForDay(
      totalTasks: dueTasks.length,
      completedTasks: completedTasks.length,
      severity: _latestSeverity(diagnoses, endOfToday),
    );
  }

  static int _scoreForDay({
    required int totalTasks,
    required int completedTasks,
    required Severity? severity,
  }) {
    final completionScore = totalTasks <= 0
        ? 100.0
        : 100.0 * (completedTasks / totalTasks).clamp(0.0, 1.0);
    return (completionScore - _severityPenalty(severity))
        .clamp(0.0, 100.0)
        .round();
  }

  static double _severityPenalty(Severity? severity) {
    switch (severity) {
      case Severity.healthy:
        return 0;
      case Severity.mild:
        return 10;
      case Severity.moderate:
        return 25;
      case Severity.severe:
        return 45;
      default:
        return 0;
    }
  }
```

**Explanation:** The calculation starts with task completion for tasks due by the end of the current day. It subtracts a penalty based on the latest diagnosis severity and clamps the result between 0 and 100. The severity lookup and score history/display code are outside this excerpt.

## F.8 Admin Authentication and Role-Based Access

**Source Files:** `ai_backend/app/services/auth_service.py` (lines 17–40); `ai_backend/app/core/dependencies.py` (lines 73–105)

**Description:** The backend derives the administrative role from trusted application metadata, requires administrator access and multi-factor verification for protected admin routes, and restricts superadmin-only routes to the superadmin role.

**Sample Source Code:**

```python
    async def verify_access_token(self, access_token: str) -> AuthenticatedUser:
        if not self._settings.supabase_url or not self._settings.supabase_service_role_key:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Supabase auth is not configured on the backend.",
            )

        user_payload = await self._supabase.get_user(access_token)
        if not user_payload:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid access token.",
            )

        app_metadata = user_payload.get("app_metadata")
        trusted_metadata = app_metadata if isinstance(app_metadata, dict) else {}
        admin_role = str(trusted_metadata.get("admin_role") or "").strip().lower()

        return AuthenticatedUser(
            id=user_payload.get("id", ""),
            email=user_payload.get("email"),
            role=admin_role or "authenticated",
            assurance_level=self._assurance_level(access_token),
        )
```

```python
async def require_admin_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    auth_service: AuthService = Depends(get_auth_service),
) -> AuthenticatedUser:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Administrator sign-in is required.",
        )

    user = await auth_service.verify_access_token(credentials.credentials)
    if user.role not in {"admin", "superadmin"}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Administrator access is required.",
        )
    if user.assurance_level != "aal2":
        raise HTTPException(
            status_code=status.HTTP_428_PRECONDITION_REQUIRED,
            detail="Multi-factor verification is required.",
        )
    return user


async def require_superadmin_user(
    admin: AuthenticatedUser = Depends(require_admin_user),
) -> AuthenticatedUser:
    if admin.role != "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Superadmin access is required.",
        )
    return admin
```

**Explanation:** A valid access token is required before the backend accepts an administrative role. Admin routes require either the `admin` or `superadmin` role and the specified assurance level. A superadmin route adds a further role check. The excerpts depend on the authentication service, Supabase client, and related types.

## F.9 Superadmin Management of Administrator Access

**Source Files:** `ai_backend/public/admin.js` (lines 1610–1625); `ai_backend/app/api/admin.py` (lines 190–202); `ai_backend/app/services/admin_service.py` (lines 834–885)

**Description:** The admin website confirms the requested role change and calls a protected API route. The route requires a superadmin, and the service updates or removes the target user's administrator role while preventing changes to the acting user's own role or to a superadmin account.

**Sample Source Code:**

```javascript
async function updateAdminRole(user, approved) {
  const declining = !approved && user.admin_access_requested && !user.admin_role;
  const verb = approved
    ? "approve administrator access for"
    : declining ? "decline the administrator request from" : "revoke administrator access from";
  if (!window.confirm(`${verb[0].toUpperCase()}${verb.slice(1)} ${user.email}?`)) return;
  try {
    await api(`/v1/admin/users/${encodeURIComponent(user.id)}/admin-role`, {
      method: "PATCH",
      body: JSON.stringify({ approved }),
    });
    showStatus(approved
      ? "Administrator access approved."
      : declining ? "Administrator request declined." : "Administrator access revoked.");
    await renderUsers();
  } catch (failure) { showStatus(failure.message, true); }
}
```

```python
@router.patch("/users/{user_id}/admin-role", status_code=status.HTTP_204_NO_CONTENT)
async def set_user_admin_role(
    user_id: str,
    payload: dict[str, Any],
    superadmin: AuthenticatedUser = Depends(require_superadmin_user),
    service: AdminService = Depends(get_admin_service),
) -> Response:
    await service.set_user_admin_role(
        user_id,
        approved=payload.get("approved") is True,
        actor=superadmin,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
```

The service applies the role change:

```python
    async def set_user_admin_role(
        self,
        user_id: str,
        *,
        approved: bool,
        actor: AuthenticatedUser,
    ) -> None:
        if actor.role != "superadmin":
            raise HTTPException(status_code=403, detail="Superadmin access is required.")
        if actor.id == user_id:
            raise HTTPException(status_code=409, detail="You cannot change your own administrator role.")

        url = f"{self._settings.supabase_url}/auth/v1/admin/users/{user_id}"
        async with httpx.AsyncClient(timeout=15.0) as client:
            lookup = await client.get(url, headers=self._headers())
        self._raise_for_response(lookup)
        target = lookup.json()
        existing_metadata = target.get("app_metadata") if isinstance(target, dict) else {}
        metadata = dict(existing_metadata) if isinstance(existing_metadata, dict) else {}
        existing_user_metadata = target.get("user_metadata") if isinstance(target, dict) else {}
        user_metadata = dict(existing_user_metadata) if isinstance(existing_user_metadata, dict) else {}
        requested = user_metadata.get("admin_access_requested") is True
        current_role = str(metadata.get("admin_role") or "").strip().lower()
        if current_role == "superadmin":
            raise HTTPException(
                status_code=409,
                detail="Superadmin roles can only be managed by the Supabase project owner.",
            )

        if approved:
            metadata["admin_role"] = "admin"
        else:
            metadata.pop("admin_role", None)
        update_payload: dict[str, Any] = {"app_metadata": metadata}
        if requested:
            user_metadata.pop("admin_access_requested", None)
            update_payload["user_metadata"] = user_metadata
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.put(
                url,
                headers=self._headers(),
                json=update_payload,
            )
        self._raise_for_response(response)
        await self._audit(
            actor,
            "approve" if approved else "decline" if requested else "revoke",
            "users",
            user_id,
            {"admin_role": "admin" if approved else None},
        )
```

**Explanation:** The website presents a confirmation before submitting an approval, decline, or revocation request. The API route is protected by the superadmin dependency. The service validates the actor and target account, changes the `admin_role` metadata, and records the action. HTTP helpers, audit implementation, and other user-management actions are not shown.

## Scope and Omitted Components

These samples document the verified implementations listed above; they do not represent every screen or service in the project. Separate complete excerpts for camera/gallery acquisition, AI-generated daily progress analysis, announcement management, disease and agricultural content administration, and the full crop-management workflow are not included in this appendix. Their omission here should not be taken as evidence that the features are absent.
