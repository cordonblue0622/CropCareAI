# Appendix E – User Manual

This appendix explains how to use the CropCare AI mobile application and its
administrative website. It is based on the currently implemented application.
Buttons and available actions can vary by account role and the information
available to that account.

---

## E.1 End User Manual – Mobile Application

### E.1.1 Purpose and intended users

CropCare AI is a mobile assistant for vegetable farmers. It helps users review
crop photos, ask questions about plant problems, keep crop-care tasks, record
daily progress, and review crop health information. The application is intended
for farmers and other people who care for supported vegetable crops, including
users who prefer simple, step-by-step instructions.

The application supports tomato, bell pepper, squash, eggplant, and pechay.
An AI result is an aid for inspection, not a guarantee that a disease has been
confirmed. Check the plant and follow local agricultural guidance before taking
important action.

### E.1.2 System requirements

1. **Mobile platforms:** The project includes Android and iOS applications.
2. **Android:** The provided release APK requires Android 7.0 (API level 24)
   or later. The examined APK is version 1.0.15, build 14.
3. **iOS:** The project specifies iOS 13.0 or later. An iOS installation
   package is not included with the Android APK; use the distribution method
   provided by the project or organization.
4. **Internet:** Internet is needed for account services and online features
   such as AI chat, weather information, and syncing. Some saved information
   and supported scan functions can remain available offline, but offline use
   does not provide every online feature.
5. **Camera and media:** A camera is needed to take photos or record video.
   Users can choose a photo from the device gallery instead. Crop photos and
   videos need available device storage.
6. **Optional permissions:** Camera access is needed for in-app capture.
   Microphone and speech access are used for voice features. Photo or media
   access is needed to select images. Notification access supports reminders.
   Android may also request alarm-related permission so scheduled reminders
   can run. Users can deny permissions, but the related feature may not work.
7. **Location:** The user enters a farm location in the profile or crop details.
   The documented app flow does not use GPS to determine the farm location.

### E.1.3 Install and get started

#### Install the Android APK

1. Obtain `CropCareAI-release.apk` from the official project or organization
   distribution channel.
2. Open the downloaded APK on the Android device.
3. If Android asks whether this source may install applications, allow it only
   for this trusted file and continue.
4. Tap **Install**, wait for installation to finish, then tap **Open**.
5. On the start screen, choose **Get Started** to register, or **Sign In** if
   an account already exists.

Do not install an APK received from an unknown source. The APK is for Android;
it cannot be installed on an iPhone or iPad.

#### Register an account

1. On the start screen, tap **Get Started**.
2. Enter your full name and email address.
3. Enter your farm location: country, province or state, municipality or city,
   and barangay or village.
4. Create a password.
5. Read and agree to the Terms of Service and Privacy Policy.
6. Tap **Create Account**.
7. If the application asks you to verify your email, open the email message and
   follow its verification link. Return to the application and sign in.
8. After successful registration or sign-in, the application opens the main
   area.

#### Sign in or reset a password

1. Tap **Sign In** on the start screen.
2. Enter your email address and password, then tap **Sign In**.
3. If you have forgotten your password, enter your email address and tap
   **Forgot Password?**. Follow the instructions sent to your email.

The mobile application offers email-and-password sign-in. No social sign-in
option is shown.

**[Insert Screenshot: CropCare AI Start and Sign-In Screens]**

*Figure E.1.1. Start screen and sign-in form.*

**[Insert Screenshot: CropCare AI Registration Form]**

*Figure E.1.2. Registration form with farm-location fields.*

### E.1.4 Dashboard and navigation

The bottom navigation bar contains five main destinations:

1. **Home** – Opens the dashboard.
2. **Crops** – Opens the list of crops saved to the account.
3. **Scan** – Opens the crop-photo and video scanning flow.
4. **Voice** – Opens the voice assistant.
5. **Account** – Opens profile and application settings.

The Home dashboard can show a greeting, weather, notifications, search, Farm
Vitality, active crops, today's tasks, smart tips, and common-disease
information. Tap a card or item to open the related feature. The profile or
avatar menu also provides routes to items such as diagnosis history and the
disease library.

**[Insert Screenshot: CropCare AI End User Dashboard]**

*Figure E.1.3. Home dashboard and bottom navigation.*

### E.1.5 Scan a vegetable photo or video

1. Tap **Scan** in the bottom navigation.
2. Allow camera access if you want to take a new photo or record a video.
   If you do not want to use the camera, choose a photo from the gallery.
3. For a photo, hold the camera steady and show the affected plant area. For a
   video, record a short clip in the scan screen. The in-app recording stops
   after 15 seconds.
4. Review the photo or video preview.
5. Choose the crop family shown in the picture: tomato, bell pepper, squash,
   eggplant, or pechay. The crop choice is required before continuing.
6. If helpful, type a short note about what you noticed.
7. Tap **Continue** to submit the image for analysis and open the AI chat.

The scan flow supports gallery photos. It does not show a video-gallery picker;
video is recorded in the app. A crop-family choice guides the review but does
not by itself confirm the plant or a disease.

**[Insert Screenshot: Scan Camera and Gallery Controls]**

*Figure E.1.4. Scan screen with photo and video controls.*

**[Insert Screenshot: Image Preview and Crop-Family Selection]**

*Figure E.1.5. Preview screen with required crop selection.*

### E.1.6 Read a diagnosis and talk with the AI assistant

1. After submitting a scan, wait for the assistant to review the available
   image and crop information.
2. Read the assistant's reply. It may describe visible signs, give a likely
   condition, explain uncertainty, or ask for one detail needed to improve the
   assessment.
3. If the assistant asks a question, answer it in the message box. Do not
   repeat the crop family if you have already selected or provided it.
4. Ask a follow-up question, such as what may have caused the problem, whether
   a plant may recover, or what care steps to take.
5. Tap the send button to submit your message.
6. Use the camera or image attachment controls to include another photo when
   it is useful. The chat can attach photos; it can also use its voice-input
   controls where available.
7. If a treatment card appears, read its actions and follow the steps that
   apply to your crop. Check product labels and local advice before applying
   any chemical.

The AI can make mistakes, and a photo may not show enough detail to identify
the cause. A local scan can be available when internet service is unavailable,
but online chat, weather, and syncing depend on connectivity.

**[Insert Screenshot: AI Diagnosis and Follow-Up Chat]**

*Figure E.1.6. Assistant response and chat input.*

### E.1.7 My Crops

1. Tap **Crops** at the bottom of the screen.
2. Review the saved crop cards. A card may show the crop name and type, plot
   code, status, latest health score, and last update.
3. Use the search or crop-type filter to find a crop. Active and treated crops
   are shown in their respective groups.
4. To add a crop, use the add-crop action or the **Add to My Crops** option
   when it is offered with a diagnosis. Enter the requested crop details and
   save.
5. Tap a crop card to open its details.
6. Use a crop's options menu for the available crop actions, such as deletion.

The crop list's edit option may not open an edit form. When you need to change
crop details, open the crop and use the edit control on its detail screen.

**[Insert Screenshot: My Crops List and Crop Card]**

*Figure E.1.7. My Crops list with crop status and health information.*

### E.1.8 Crop details, treatment recommendations, and daily tasks

Crop details are organized into **Overview**, **Daily Plan**, **Progress**, and
**Diagnoses** tabs.

1. Open a crop from **Crops**.
2. In **Overview**, review the crop's summary and saved details.
3. Open **Daily Plan** to see the current treatment day and its care actions.
4. Complete an action in the field. Return to the plan and mark that task as
   done.
5. From the Home dashboard, tap a due or overdue task to open the matching
   crop's Daily Plan.
6. Complete the day's listed actions before submitting the daily check-in.

Treatment actions and schedules depend on the diagnosis and the crop-care
information available in the application. Read each instruction carefully.
The dashboard task list opens the relevant plan; tasks are marked complete
from the plan.

**[Insert Screenshot: Crop Details and Daily Plan]**

*Figure E.1.8. Crop detail tabs and daily treatment actions.*

### E.1.9 Submit daily progress and AI analysis

1. Open the crop's **Daily Plan** after completing that day's actions.
2. Start the daily check-in when it is available.
3. Add a photo of the crop; a photo is required for the image-based AI
   assessment.
4. Add notes if you wish. Voice dictation and video evidence are optional
   where shown.
5. Submit the check-in and review the returned assessment or health
   information.
6. If the device is offline, the assessment may remain pending until the
   information can sync.

**[Insert Screenshot: Daily Check-In and Photo Submission]**

*Figure E.1.9. Daily progress check-in with photo evidence.*

### E.1.10 Farm Vitality and health scores

The Home dashboard's **Farm Vitality** section summarizes available health
scores for active crops. It can show crop-level scores and trends. A crop with
no check-in may show that a score is still awaited.

1. Find **Farm Vitality** on the Home dashboard.
2. Review the overall summary and individual crop scores.
3. Tap a crop or its score to open that crop's **Progress** tab.
4. Use the Progress view to review dated updates, the health-score graph, and
   visual changes recorded over time.

Scores summarize the information available to the application; they are not a
guarantee of future crop performance.

**[Insert Screenshot: Farm Vitality and Crop Progress Graph]**

*Figure E.1.10. Farm Vitality overview and an individual crop's progress.*

### E.1.11 Disease awareness, weather, and notifications

1. Review the **Common Diseases** or disease-information cards on the Home
   dashboard.
2. Tap a card to open the related information in the disease library.
3. Open the weather information from the dashboard to review current
   conditions, an hourly temperature/rain/wind view, and the available
   forecast days.
4. Keep the farm location in your profile or crop details current so the
   weather feature can use it. The app uses entered location information in
   the documented flow; it does not automatically locate the device.
5. Review the notification area and any task reminders. Notifications support
   upcoming, due, and overdue care tasks.

Disease-library information is selected for crop types in the account. The
implemented screens do not provide a GPS-based disease outbreak forecast or
location-specific disease-risk alert. Weather and general care tips may help
with planning, but they are not outbreak warnings.

**[Insert Screenshot: Disease Information and Weather Sheet]**

*Figure E.1.11. Crop-related disease information and location-based weather.*

### E.1.12 Diagnosis and conversation history

#### Review diagnosis history

1. Open the profile/avatar menu from the Home area.
2. Choose **Diagnostic History**.
3. Browse the saved diagnosis and crop-added entries.
4. Tap an entry to open its linked conversation when one exists. If no linked
   conversation is available, the app opens the relevant crop details.

#### Continue or start a chat

1. Open **Vegetable Doctor** or a saved diagnosis conversation.
2. Tap the history control in the chat header to view previous conversations.
3. Select a conversation to continue it, or use the new-chat control to start
   another conversation.

**[Insert Screenshot: Diagnostic History and Chat History]**

*Figure E.1.12. Saved diagnosis entries and the conversation history menu.*

### E.1.13 Profile, settings, and sign out

1. Tap **Account** in the bottom navigation to open account details and
   settings.
2. Use the profile edit option to update available personal and farm details.
   If you change your email address, follow the confirmation instructions
   sent to the new address.
3. Use the device-permission option when you need to review notification or
   other app permissions in the operating system.
4. Open notification sound settings to turn reminder sounds on or off.
5. Tap **Sign Out** and confirm when asked.

**[Insert Screenshot: Account Profile and Settings]**

*Figure E.1.13. Account details, reminder settings, and sign-out control.*

---

## E.2 Admin Manual – Admin Website

### E.2.1 Purpose and access

The Admin Website is for authorized CropCare AI administrators who manage
announcements, user accounts, crop records, disease information, treatment
protocols, and administrative reports. An account registration request alone
does not grant administrator access.

1. Open the Admin Website using the address provided by the organization.
   The project website uses an `/admin` page; the production host address is
   deployment-specific.
2. Enter the approved administrator email and password.
3. Complete the authenticator-code step when prompted. A first-time admin may
   be asked to set up an authenticator before the website opens.
4. After sign-in, use the left-side menu to open a section.

If you do not yet have admin access, use **Create an account** on the sign-in
page, enter the requested details, and confirm your email. Ask a Superadmin
to approve the request. Registration alone does not provide admin privileges.

**[Insert Screenshot: Admin Website Sign-In and Authenticator Prompt]**

*Figure E.2.1. Admin Website sign-in and verification screen.*

### E.2.2 Dashboard and navigation

The Admin Website sidebar contains the following sections:

1. **Overview** – Summary totals for managed users, crops, treatments, and
   diseases.
2. **Announcements** – Create posts and read the announcement timeline.
3. **User Management** – View and manage user accounts within your role's
   permissions.
4. **Disease Library** – Maintain disease information.
5. **Treatments** – Maintain crop-and-disease treatment protocols.
6. **Crop Data** – Review and manage registered crop records.
7. **Analytics** – Review user, crop, treatment-task, and diagnosis summaries.
8. **System Data** – Review recent administrative activity records.

The Admin and Superadmin dashboards use the same main sections. Actions inside
those sections depend on your role.

**[Insert Screenshot: Admin Website Overview and Sidebar]**

*Figure E.2.2. Admin dashboard and navigation menu.*

### E.2.3 Create and manage announcements

1. Open **Announcements**.
2. Enter a title and message.
3. Choose one audience:
   - **Administrators only** for an announcement intended for the admin
     website audience.
   - **All app users** for an announcement intended for mobile application
     users.
4. Review the title, message, and audience, then publish the announcement.
5. Find the post on the timeline.
6. Use the like control to like or remove your like. Use the reply control to
   add a reply. The timeline displays like and reply counts, reply authors,
   and timestamps.

Selecting **All app users** makes the announcement available to mobile users
through the app's notification feature. The website does not offer more
detailed audience targeting. The current announcement interface does not
provide edit or delete controls.

**[Insert Screenshot: Announcement Composer and Audience Choices]**

*Figure E.2.3. Announcement form and audience selection.*

**[Insert Screenshot: Announcement Timeline, Likes, and Replies]**

*Figure E.2.4. Announcement timeline and supported interactions.*

### E.2.4 Manage ordinary user accounts

1. Open **User Management** and select the user list.
2. To invite a regular mobile-app user, choose **Add User**, enter the
   requested information, and send the invitation. The user completes the
   email step and sets their own password.
3. Select an ordinary user's row to edit the profile or send a password-reset
   email.
4. Use **Suspend** to temporarily suspend an ordinary user's account, or
   **Restore** to restore a suspended account.

An Admin can manage ordinary users, but cannot approve or revoke admin access,
invite another Admin, or manage an Admin's account. The website does not show
or directly set a user's password.

**[Insert Screenshot: User Management and User Actions]**

*Figure E.2.5. User list and available ordinary-user actions.*

### E.2.5 Review crop data

1. Open **Crop Data**.
2. Expand a user to view the crops registered to that user.
3. Select a crop to inspect its available details and activity.
4. Use the available edit or archive action when a crop record needs attention.

This area manages registered user crop records. It is not a separate catalog
for defining crop species or agricultural crop knowledge.

**[Insert Screenshot: Crop Data and Crop Record Details]**

*Figure E.2.6. Registered crop records in the Admin Website.*

### E.2.6 Maintain the disease library

1. Open **Disease Library**.
2. Select the crop group for the information you need.
3. Choose the add or edit action.
4. Enter or update the disease information shown in the form, such as symptoms,
   causes, severity, prevention and treatment guidance, and sources.
5. Save the record. Use **Deactivate** when the record should no longer be
   active in the library.

**[Insert Screenshot: Disease Library Editor]**

*Figure E.2.7. Crop-group selection and disease information form.*

### E.2.7 Maintain treatment protocols

1. Open **Treatments**.
2. Select a crop and a disease.
3. Add or edit the protocol, including its duration and day-by-day care steps.
4. Review the entries and save.

The Treatments section manages the curated crop-care protocol. It is separate
from a user's individual task completion in the mobile application.

**[Insert Screenshot: Treatment Protocol Editor]**

*Figure E.2.8. Treatment protocol duration and daily steps.*

### E.2.8 Review analytics and system activity

1. Open **Analytics** to review the available summaries for users, crop
   activity, treatment tasks, and diagnoses.
2. Open **System Data** to review recent administrative activity records.
3. Use **Overview** to return to the management totals.

**[Insert Screenshot: Admin Analytics and System Data]**

*Figure E.2.9. Administrative summaries and recent system activity.*

### E.2.9 Admin role limits

- Admins can manage ordinary users and the crop, disease, and treatment
  information described above.
- Admins cannot approve, decline, or revoke administrator roles.
- Admins cannot invite another Admin or manage an Admin account. Those
  functions are reserved for a Superadmin.
- The website does not provide a way to create a Superadmin account.
- The announcement timeline has like and reply actions, but no edit or delete
  action was found.

---

## E.3 Superadmin Manual – Admin Website

### E.3.1 Purpose and access

The Superadmin role is for authorized system administrators who oversee
administrator access as well as the content and user-management areas of the
Admin Website.

1. Open the Admin Website address provided by the organization.
2. Enter the approved Superadmin email and password.
3. Complete the authenticator-code step when prompted. A first-time
   Superadmin may be asked to set up an authenticator.
4. Confirm that the signed-in identity shows the Superadmin role before
   performing system-level account actions.

The website's user invitation flow does not create Superadmin accounts.
Superadmin access must be provided through the organization's approved
account-provisioning process.

**[Insert Screenshot: Superadmin Sign-In and Role Identity]**

*Figure E.3.1. Superadmin sign-in and role indicator.*

### E.3.2 Dashboard and navigation

After sign-in, use the sidebar sections:

1. **Overview** for management totals.
2. **Announcements** for announcements and the discussion timeline.
3. **User Management** for ordinary users and administrator access.
4. **Disease Library** for crop disease information.
5. **Treatments** for crop-and-disease protocols.
6. **Crop Data** for registered crop records.
7. **Analytics** for activity summaries.
8. **System Data** for recent administrative activity.

The Superadmin dashboard uses the same main sections as the Admin dashboard.
The additional Superadmin actions are available within **User Management**.

**[Insert Screenshot: Superadmin Overview and Sidebar]**

*Figure E.3.2. Superadmin dashboard and navigation menu.*

### E.3.3 Approve or remove administrator access

1. Open **User Management**, then open the **Admins** area.
2. Review pending administrator-access requests.
3. Choose **Approve** to grant the applicant Admin access, or **Decline** to
   reject the request.
4. To remove an existing Admin's privileges, choose the revoke action on that
   Admin's row and confirm when asked.

Revoking an Admin role removes that administrator's privileges; it does not
delete the underlying account. The current website prevents a Superadmin from
changing their own role or targeting another Superadmin.

**[Insert Screenshot: Pending Admin Requests and Approval Actions]**

*Figure E.3.3. Administrator requests and approval controls.*

### E.3.4 Invite a user or an Admin

1. Open **User Management** and choose **Add User**.
2. Enter the invitee's requested details.
3. Choose the available role:
   - Choose **User** for a regular mobile-application account.
   - Choose **Admin** when the invitation should grant administrator access.
4. Send the invitation. The invitee follows the email instructions and sets
   their own password.

The invitation form offers User and Admin roles. It does not offer
Superadmin, and it does not provide a way to promote the signed-in account to
Superadmin.

**[Insert Screenshot: Superadmin Invitation and Role Selection]**

*Figure E.3.4. User invitation form with role selection.*

### E.3.5 Suspend, restore, and manage accounts

1. In **User Management**, locate the account to manage.
2. Select **Suspend** to temporarily suspend an ordinary user or, when
   authorized, another Admin.
3. Select **Restore** to restore a suspended account.
4. Use the profile-edit or password-reset action when available for the
   selected account.
5. Do not confuse suspension with revoking an Admin role:
   - **Suspend** temporarily disables account access and can be reversed with
     **Restore**.
   - **Revoke Admin** removes the Admin role but does not delete the account.

A Superadmin cannot suspend their own account or manage another Superadmin
through these controls. The website does not provide a permanent account
deletion action in this workflow.

**[Insert Screenshot: Admin Account Suspend, Restore, and Revoke Controls]**

*Figure E.3.5. Superadmin account-management actions.*

### E.3.6 Maintain crop, disease, treatment, and announcement information

Superadmins can use the same content and announcement areas described in this
manual:

1. Use **Crop Data** to inspect and manage registered user crop records.
2. Use **Disease Library** to add, edit, or deactivate disease information.
3. Use **Treatments** to add or edit crop-specific treatment protocols and
   daily steps.
4. Use **Announcements** to publish to **Administrators only** or **All app
   users**, then use the timeline's like and reply controls.
5. Use **Analytics** and **System Data** to review summaries and recent
   administrative activity.

The Superadmin role has additional account-management permissions. The
current website does not provide a Superadmin role editor, a Superadmin
creation action, or announcement edit/delete controls.

**[Insert Screenshot: Superadmin Disease, Treatment, and Announcement Tools]**

*Figure E.3.6. Superadmin content-management areas.*

---

## E.4 Documentation notes

1. The Admin Website's production address, account-provisioning process, and
   authenticator setup policy are supplied by the organization and cannot be
   determined from the application screens alone.
2. The documented Android minimum is taken from the provided release APK.
   The iOS project specifies iOS 13.0; a distributable iOS package was not
   available for this manual.
3. The Admin Website implements temporary account suspension and restoration
   and Admin-role revocation. These are different actions; no permanent
   account deletion workflow was identified in the reviewed user-management
   screens.
4. This appendix uses screenshot placeholders only. Actual screenshots are
   to be supplied separately and should not contain real account credentials,
   private user information, or unpublished farm data.
