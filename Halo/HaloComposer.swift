//
//  HaloComposer.swift
//  Halo
//
//  Setting your own halo, and deciding how long to wear it.
//

import SwiftUI

struct HaloComposer: View {
    @Binding var draft: HaloDraft
    let controller: BroadcastController

    @State private var length: BroadcastSession.Length = .oneHour
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Your halo")
                } footer: {
                    Text("This is what people around you would see floating above your head.")
                }

                Section("What you're broadcasting") {
                    TextField("Name", text: $draft.name)
                        .onChange(of: draft) { _, _ in draft = draft.clamped }
                    TextField("Say something", text: $draft.message, axis: .vertical)
                        .lineLimit(1...3)

                    HStack {
                        Text("Colour")
                        Spacer()
                        ForEach(HaloDraft.palette.indices, id: \.self) { index in
                            Circle()
                                .fill(HaloDraft.palette[index])
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if index == draft.tintIndex {
                                        Circle().strokeBorder(.primary, lineWidth: 2)
                                    }
                                }
                                .onTapGesture { draft.tintIndex = index }
                        }
                    }
                }

                if controller.isBroadcasting() {
                    Section {
                        LabeledContent("Visible for another",
                                       value: remainingText)
                        Button("Stop broadcasting", role: .destructive) {
                            controller.stop()
                        }
                    } footer: {
                        Text("Halos are always time-boxed, so you never end up broadcasting "
                             + "without realising it. A force-quit also stops it.")
                    }
                } else {
                    Section {
                        Picker("Broadcast for", selection: $length) {
                            ForEach(BroadcastSession.Length.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        Button("Start broadcasting") {
                            controller.start(draft.profile, for: length)
                        }
                        .disabled(!draft.isBroadcastable)
                    } footer: {
                        Text("Only people nearby who are pointing Halo at you can see it, "
                             + "and you are never told when someone looks.")
                    }
                }
            }
            .navigationTitle("Your halo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The balloon exactly as others would see it — the "look up and see your
    /// own halo" promise, in the form a phone can manage.
    private var preview: some View {
        VStack(spacing: 0) {
            if draft.isBroadcastable {
                HaloBubble(profile: draft.profile)
                    .fixedSize()
            } else {
                Text("Nothing yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(.primary.opacity(0.35))
                .frame(width: 1.5, height: 26)

            Circle()
                .fill(HaloDraft.palette[min(draft.tintIndex, HaloDraft.palette.count - 1)])
                .frame(width: 20, height: 20)

            Image(systemName: "person.fill")
                .font(.title)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    private var remainingText: String {
        let remaining = Int(controller.remaining())
        let minutes = remaining / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return minutes > 0 ? "\(minutes) min" : "under a minute"
    }
}
