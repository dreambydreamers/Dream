import PhotosUI
import SwiftUI

/// Lets the signed-in user edit their profile (avatar, name, @handle, location,
/// skills) and pick which dream is featured ("main") on their profile. Presented
/// as a sheet from `ProfileScreen`; calls `onSaved` after a successful write.
/// The avatar persists immediately on pick/remove, independent of the form save.
struct EditProfileScreen: View {
    let userId: UUID
    let avatarSeed: Int
    let dreams: [Dream]
    var onSaved: () -> Void = {}
    var onCancel: () -> Void = {}

    @State private var name: String
    @State private var handle: String   // handle = username
    @State private var location: String
    @State private var skills: [String]
    @State private var newSkill: String = ""
    @State private var featuredDreamId: UUID?
    @State private var initialFeaturedId: UUID?

    @State private var avatarURL: URL?
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarBusy = false
    @State private var avatarError: String?

    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        userId: UUID,
        name: String,
        handle: String,
        location: String,
        skills: [String],
        avatarSeed: Int = 0,
        avatarURL: URL? = nil,
        dreams: [Dream],
        onSaved: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) {
        self.userId = userId
        self.avatarSeed = avatarSeed
        self.dreams = dreams
        self.onSaved = onSaved
        self.onCancel = onCancel
        _name = State(initialValue: name)
        _handle = State(initialValue: handle)
        _location = State(initialValue: location)
        _skills = State(initialValue: skills)
        _avatarURL = State(initialValue: avatarURL)
        let featured = dreams.first(where: { $0.isFeatured })?.id
        _featuredDreamId = State(initialValue: featured)
        _initialFeaturedId = State(initialValue: featured)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DreamTheme.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    avatarSection
                    field("Name", text: $name, placeholder: "Your name")
                    field("Username", text: $handle, placeholder: "username", prefix: "@", autocap: false)
                    field("Location", text: $location, placeholder: "City, Country")
                    skillsSection
                    if !dreams.isEmpty { mainDreamSection }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(DreamTheme.Font.text(13))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 76)
                .padding(.bottom, 60)
            }

            topBar
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(DreamTheme.Font.text(15))
                .foregroundStyle(DreamTheme.ink2)
            Spacer()
            Text("Edit Profile")
                .font(DreamTheme.Font.display(18, weight: .medium))
                .foregroundStyle(DreamTheme.ink)
            Spacer()
            Button(action: save) {
                if isSaving {
                    ProgressView().tint(DreamTheme.blue)
                } else {
                    Text("Save")
                        .font(DreamTheme.Font.text(15, weight: .semibold))
                        .foregroundStyle(DreamTheme.blue)
                }
            }
            .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(DreamTheme.paper)
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $avatarItem, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    Avatar(name: name, seed: avatarSeed, size: 96, url: avatarURL)
                        .overlay(Circle().strokeBorder(DreamTheme.line, lineWidth: 1))
                        .opacity(avatarBusy ? 0.5 : 1)
                    if avatarBusy {
                        ProgressView().tint(DreamTheme.blue)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(DreamTheme.blue))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(avatarBusy)

            if avatarURL != nil {
                Button("Remove photo", action: removeAvatar)
                    .font(DreamTheme.Font.text(13, weight: .semibold))
                    .foregroundStyle(.red)
                    .disabled(avatarBusy)
            }

            if let avatarError {
                Text(avatarError)
                    .font(DreamTheme.Font.text(12))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            uploadAvatar(item)
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) {
        avatarBusy = true
        avatarError = nil
        Task {
            defer { avatarBusy = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    avatarError = "Couldn't load that image."
                    return
                }
                let urlString = try await AvatarUploader.shared.upload(image)
                try await ProfileRepository.shared.updateAvatar(userId: userId, avatarURL: urlString)
                avatarURL = URL(string: urlString)
            } catch {
                print("[EditProfileScreen] avatar upload failed: \(error)")
                avatarError = avatarMessage(for: error, fallback: "Couldn't update your photo. Please try again.")
            }
        }
    }

    private func removeAvatar() {
        avatarBusy = true
        avatarError = nil
        Task {
            defer { avatarBusy = false }
            do {
                try await AvatarUploader.shared.remove()
                try await ProfileRepository.shared.updateAvatar(userId: userId, avatarURL: nil)
                avatarURL = nil
                avatarItem = nil
            } catch {
                print("[EditProfileScreen] avatar remove failed: \(error)")
                avatarError = avatarMessage(for: error, fallback: "Couldn't remove your photo. Please try again.")
            }
        }
    }

    private func avatarMessage(for error: Error, fallback: String) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        let message = error.localizedDescription
        return message == "The operation couldn’t be completed. (PostgREST.PostgrestError error 0.)" ? fallback : message
    }

    // MARK: - Text field

    private func field(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        prefix: String? = nil,
        autocap: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow(label)
            HStack(spacing: 2) {
                if let prefix {
                    Text(prefix)
                        .font(DreamTheme.Font.text(16, weight: .medium))
                        .foregroundStyle(DreamTheme.ink2)
                }
                TextField(placeholder, text: text)
                    .font(DreamTheme.Font.text(16))
                    .foregroundStyle(DreamTheme.ink)
                    .textInputAutocapitalization(autocap ? .words : .never)
                    .autocorrectionDisabled(!autocap)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DreamTheme.line, lineWidth: 1))
        }
    }

    // MARK: - Skills

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Skills")
            if !skills.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(skills, id: \.self) { skill in
                        HStack(spacing: 6) {
                            Text(skill)
                                .font(DreamTheme.Font.text(13, weight: .semibold))
                                .foregroundStyle(DreamTheme.blueDeep)
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DreamTheme.blueDeep.opacity(0.7))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(DreamTheme.blueSoft))
                        .onTapGesture { skills.removeAll { $0 == skill } }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Add a skill", text: $newSkill)
                    .font(DreamTheme.Font.text(15))
                    .foregroundStyle(DreamTheme.ink)
                    .onSubmit(addSkill)
                Button(action: addSkill) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(DreamTheme.blue)
                }
                .buttonStyle(.plain)
                .disabled(newSkill.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DreamTheme.line, lineWidth: 1))
        }
    }

    private func addSkill() {
        let trimmed = newSkill.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !skills.contains(trimmed) else { return }
        skills.append(trimmed)
        newSkill = ""
    }

    // MARK: - Main dream

    private var mainDreamSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Main Dream")
            Text("Featured at the top of your profile.")
                .font(DreamTheme.Font.text(13))
                .foregroundStyle(DreamTheme.ink2)
            VStack(spacing: 0) {
                ForEach(dreams) { dream in
                    Button { featuredDreamId = dream.id } label: {
                        HStack(spacing: 12) {
                            Image(systemName: featuredDreamId == dream.id ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(featuredDreamId == dream.id ? DreamTheme.blue : DreamTheme.ink3)
                            Text(dream.title)
                                .font(DreamTheme.Font.text(15, weight: .medium))
                                .foregroundStyle(DreamTheme.ink)
                                .lineLimit(1)
                            Spacer()
                            CategoryBadge(category: dream.category, dark: true)
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    if dream.id != dreams.last?.id {
                        Rectangle().fill(DreamTheme.line).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DreamTheme.line, lineWidth: 1))
        }
    }

    // MARK: - Save

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await ProfileRepository.shared.updateProfile(
                    userId: userId,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    handle: handle.trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "@")),
                    location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                    skills: skills
                )
                if let featuredDreamId, featuredDreamId != initialFeaturedId {
                    try await DreamRepository.shared.setFeatured(dreamId: featuredDreamId, ownerId: userId)
                }
                isSaving = false
                onSaved()
            } catch {
                isSaving = false
                errorMessage = "Couldn't save. The username may already be taken."
            }
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DreamTheme.Font.text(11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(DreamTheme.ink2)
    }
}
