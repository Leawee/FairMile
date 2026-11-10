import PhotosUI
import SwiftUI
import UIKit

struct ExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExpenseDraft
    @State private var amountText: String
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    var onSave: (ExpenseDraft) -> Void

    init(draft: ExpenseDraft, onSave: @escaping (ExpenseDraft) -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: draft)
        _amountText = State(initialValue: draft.amountCents == 0 ? "" : Format.plainDollars(cents: draft.amountCents))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $draft.type) {
                    ForEach(ExpenseType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                TextField("Note", text: $draft.notes)
                if let data = draft.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose photo", systemImage: "photo")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take photo", systemImage: "camera") { showCamera = true }
                }
                Text(Copy.standardMileageReminder)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle(draft.type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.amountCents = Format.cents(fromDollars: amountText) ?? 0
                        onSave(draft)
                        dismiss()
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        draft.photoData = PhotoStore.jpeg(from: image)
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    draft.photoData = PhotoStore.jpeg(from: image)
                }
            }
        }
    }
}

enum PhotoStore {
    static func jpeg(from image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 0 ? min(1, 1600 / longest) : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.jpegData(compressionQuality: 0.7)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
