# React Conventions

### To facilitate e2e testing, add a test identification property in the following places

### Scenes
* All scenes shall have a test identification property on the root View

```typescript
const MyScene = () => {
  return (
    <View testID={'my-scene'}>
    </View>
  )
}
```
```typescript
class MyOtherScene extends Component {
  render () {
    return (
      <View testID={'my-other-scene'}>
        ...
      </View>
    )
  }
}
```

### Text Inputs
* All text inputs shall have a test identification property

```typescript
<TextInput testID={'username-input'} onChangeText={...} {...props} />
```

### Buttons
* All buttons shall have a test identification property

```typescript
<LoginButton testID={'login-button'} onPress={...} />
```
```typescript
<TouchableOpacity testID={'delete-wallet-button'} onPress={...} />
```
```typescript
<TouchableHighlight testID={'close-menu-button'} onPress={...} />
```
```typescript
<Button testID={'select-denomination-button'} onPress={...} />
```

### Modals
* All Modals shall have a test identification property

```typescript
<ResyncBlockchainModal testID={'resync-blockchain-modal'} onConfirm={...} />
```

### Scrolling Views
* All scrolling views shall have a test identification property

```typescript
<SectionList testID={'archived-wallets-list'} />
```
```typescript
<FlatList testID={'currency-settings-list'} />
```

### Other
* All components of interest shall have a test identification property

```typescript
<Slider testID={'slider'} onSlideComplete={...} />
```
