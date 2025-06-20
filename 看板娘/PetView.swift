import SwiftUI
import SDWebImageSwiftUI

struct PetView: View {
    @ObservedObject var petViewBackend: PetViewBackend

    var body: some View {
        VStack {
            TextField("我会帮助指挥官解决问题...", text: $petViewBackend.userInput)
                .padding(10)
                .background(Color.white.opacity(0.2))
                .cornerRadius(8)
                .textFieldStyle(PlainTextFieldStyle())
                .padding([.top, .leading, .trailing])
                .onSubmit {
                    petViewBackend.submitInput()
                }

            ScrollView {
                Text(petViewBackend.streamedResponse)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(petViewBackend.isThinking ? 0.6 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: 80)
            .background(Color.white.opacity(0.2))
            .cornerRadius(8)
            .padding([.leading, .trailing])

            ZStack {
                Color.clear
                AnimatedImage(name: petViewBackend.currentGif)
                    .resizable()
                    .id(petViewBackend.currentGif)
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                    .onTapGesture {
                        petViewBackend.handleTap()
                    }
            }
            .frame(width: 200, height: 200)
        }
        .onAppear {
            petViewBackend.onAppear()
        }
        .onDisappear {
            petViewBackend.onDisappear()
        }
    }
}
