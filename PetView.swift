import SwiftUI
import SDWebImageSwiftUI

struct PetView: View {
<<<<<<< HEAD
    
    // MARK: - Properties
    
    @ObservedObject var petViewBackend: PetViewBackend
    
    // MARK: - Body
    var body: some View {
        VStack {
            inputField
            chatOutput

            ZStack {
                petImage
=======
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
>>>>>>> 4fa7d00ee41c189ad6e6da7dc4b0a4715a74e682
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
<<<<<<< HEAD
    
    // MARK: - Subviews
    private var inputField: some View {
        TextField("我会帮助指挥官解决问题...", text: $petViewBackend.userInput)
            .padding(10)
            .background(Color.white.opacity(0.2))
            .cornerRadius(8)
            .textFieldStyle(PlainTextFieldStyle())
            .padding([.top, .leading, .trailing])
            .onSubmit {
                petViewBackend.submitInput()
            }
    }
    private var chatOutput: some View {
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

    }
    private var petImage: some View {
        AnimatedImage(name: petViewBackend.currentGif)
            .resizable()
            .id(petViewBackend.currentGif)
            .scaledToFit()
            .frame(width: 300, height: 300)
            .onTapGesture {
                petViewBackend.handleTap()
            }
    }
=======
>>>>>>> 4fa7d00ee41c189ad6e6da7dc4b0a4715a74e682
}
